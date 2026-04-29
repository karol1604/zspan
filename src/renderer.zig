const std = @import("std");

const Config = @import("config.zig").Config;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Label = @import("diagnostic.zig").Label;
const LineCol = @import("utils.zig").LineCol;
const sf = @import("sourcefile.zig");
const SourceFile = sf.SourceFile;
const utils = @import("utils.zig");

const LabeledLine = struct {
    number: usize, // 1-indexed
    range: utils.Range, // byte range
    labels: []const Label, // labels that apply to this line
};

const LabeledFile = struct {
    fileId: usize,
    lines: []LabeledLine, // lines should be sorted by line number
};

const LabeledLineBuilder = struct {
    number: usize,
    range: utils.Range,
    labels: std.ArrayList(Label),
};

const LabeledFileBuilder = struct {
    file_id: usize,
    lines: std.ArrayList(LabeledLineBuilder),
};

const VisualLabel = struct {
    label: Label,
    startCol: usize,
    endCol: usize,
    width: usize, // at least 1
    anchorCol: usize, // col where connector will be renderer
    lane: usize = 0,
};

const UnderlineLane = struct {
    labels: std.ArrayList(VisualLabel),
    endCol: usize,
};

fn findOrCreateLabeledFile(
    files: *std.ArrayList(LabeledFileBuilder),
    file_id: usize,
    alloc: std.mem.Allocator,
) !*LabeledFileBuilder {
    for (files.items) |*file| {
        if (file.file_id == file_id) return file;
    }
    try files.append(alloc, .{
        .file_id = file_id,
        .lines = .empty,
    });
    return &files.items[files.items.len - 1];
}

fn findOrCreateLabeledLine(
    lines: *std.ArrayList(LabeledLineBuilder),
    number: usize,
    range: utils.Range,
    alloc: std.mem.Allocator,
) !*LabeledLineBuilder {
    for (lines.items) |*line| {
        if (line.number == number) return line;
    }
    try lines.append(alloc, .{
        .number = number,
        .range = range,
        .labels = .empty,
    });
    return &lines.items[lines.items.len - 1];
}

fn compareLabelsByStart(_: void, a: Label, b: Label) bool {
    if (a.start != b.start) return a.start < b.start;
    return a.end > b.end;
}

fn buildLabeledFiles(
    labels: []const Label,
    sources: []const SourceFile,
    alloc: std.mem.Allocator,
) ![]LabeledFile {
    var fileBuilders: std.ArrayList(LabeledFileBuilder) = .empty;

    for (labels) |label| {
        const source = sources[label.fileId];
        const lineNumber = (try source.lineCol(label.start)).line;
        const lineRange = try source.lineRange(label.start);

        const fileBuilder = try findOrCreateLabeledFile(&fileBuilders, label.fileId, alloc);
        const lineBuilder = try findOrCreateLabeledLine(&fileBuilder.lines, lineNumber, lineRange, alloc);
        try lineBuilder.labels.append(alloc, label);
    }

    var files: std.ArrayList(LabeledFile) = .empty;
    for (fileBuilders.items) |*fileBuilder| {
        std.sort.block(LabeledLineBuilder, fileBuilder.lines.items, {}, compareLabeledLines);

        for (fileBuilder.lines.items) |*lineBuilder| {
            std.sort.block(Label, lineBuilder.labels.items, {}, compareLabelsByStart);
        }

        var lines: std.ArrayList(LabeledLine) = .empty;
        for (fileBuilder.lines.items) |*lineBuilder| {
            try lines.append(alloc, .{
                .number = lineBuilder.number,
                .range = lineBuilder.range,
                .labels = try lineBuilder.labels.toOwnedSlice(alloc),
            });
        }

        try files.append(alloc, .{
            .fileId = fileBuilder.file_id,
            .lines = try lines.toOwnedSlice(alloc),
        });
    }

    return try files.toOwnedSlice(alloc);
}

fn compareLabeledLines(_: void, a: LabeledLineBuilder, b: LabeledLineBuilder) bool {
    return a.number < b.number;
}

pub const Renderer = struct {
    config: Config,
    writer: *std.io.Writer,

    pub fn init(config: Config, writer: *std.io.Writer) Renderer {
        return .{
            .config = config,
            .writer = writer,
        };
    }

    pub fn renderDiagnostic(
        self: *Renderer,
        diagnostic: Diagnostic,
        sourceFiles: []const SourceFile,
        alloc: std.mem.Allocator,
    ) !void {
        try self.renderMainMessage(diagnostic);

        const labeledFiles = try buildLabeledFiles(diagnostic.labels, sourceFiles, alloc);
        const padding = utils.digitCount(findLargestLineNumber(labeledFiles)) + 1; // +1 for the space after the line number

        for (labeledFiles) |labeledFile| {
            const source = sourceFiles[labeledFile.fileId];
            const firstLine = labeledFile.lines[0];
            const firstLabel = firstLine.labels[0];
            const firstLineCol = try source.lineCol(firstLabel.start);

            try self.renderFileHeader(source.name, firstLineCol, padding);
            try self.renderEmptyBorderLine(padding);

            for (labeledFile.lines, 0..) |labeledLine, idx| {
                try self.renderLabeledSourceLine(diagnostic, source, labeledLine, padding, alloc);

                const nextLineNum = if (idx + 1 < labeledFile.lines.len)
                    labeledFile.lines[idx + 1].number
                else
                    labeledLine.number;
                if (nextLineNum - labeledLine.number > 1) {
                    try self.renderBorderBreak(padding);
                }
            }
        }

        if (diagnostic.notes.len == 0) {
            try self.resetColor();
            return;
        }

        try self.renderEmptyBorderLine(padding);

        for (diagnostic.notes) |note| {
            try self.renderPadding(padding);
            try self.setColor(self.config.colors.border);
            try self.writer.print("{s} ", .{self.config.charset.noteMarker});
            try self.resetColor();
            try self.writer.print("{s}\n", .{note});
        }
    }

    fn compareVisualLabels(_: void, a: VisualLabel, b: VisualLabel) bool {
        if (a.startCol != b.startCol) return a.startCol < b.startCol;

        const a_len = a.endCol - a.startCol;
        const b_len = b.endCol - b.startCol;

        if (a_len != b_len) return a_len > b_len;

        if (a.label.style != b.label.style) {
            return a.label.style == .Primary;
        }

        return false;
    }

    fn buildUnderlineLanes(labels: []VisualLabel, alloc: std.mem.Allocator) ![]UnderlineLane {
        var lanes: std.ArrayList(UnderlineLane) = .empty;

        for (labels) |label| {
            var placed = false;

            for (lanes.items, 0..) |*lane, laneIdx| {
                if (lane.endCol <= label.startCol) {
                    var copy = label;
                    copy.lane = laneIdx;
                    try lane.labels.append(alloc, copy);
                    lane.endCol = copy.endCol;
                    placed = true;
                    break;
                }
            }

            if (!placed) {
                var newLane = UnderlineLane{
                    .labels = .empty,
                    .endCol = label.endCol,
                };
                var copy = label;
                copy.lane = lanes.items.len;
                try newLane.labels.append(alloc, copy);
                try lanes.append(alloc, newLane);
            }
        }

        return try lanes.toOwnedSlice(alloc);
    }

    fn renderBorderPrefix(self: *Renderer, padding: usize) !void {
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{s} ", .{self.config.charset.border});
        try self.resetColor();
    }

    fn renderLabeledSourceLine(
        self: *Renderer,
        diagnostic: Diagnostic,
        source: SourceFile,
        labeledLine: LabeledLine,
        padding: usize,
        alloc: std.mem.Allocator,
    ) !void {
        const lineRange = labeledLine.range;
        const line = source.source[lineRange.start..lineRange.end];
        try self.renderPadding(padding - utils.digitCount(labeledLine.number) - 1);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{d} {s} ", .{ labeledLine.number, self.config.charset.border });
        try self.resetColor();
        try self.writer.print("{s}\n", .{line});

        var visualLabels: std.ArrayList(VisualLabel) = .empty;

        // build visual labels for this line
        for (labeledLine.labels) |label| {
            const startCol = sf.displayCol(source.source, lineRange.start, label.start);
            const width = @max(1, sf.displayWidth(source.source, label.start, label.end));
            const endCol = startCol + width;

            const vl = VisualLabel{
                .label = label,
                .startCol = startCol,
                .endCol = endCol,
                .width = width,
                .anchorCol = startCol,
            };
            try visualLabels.append(alloc, vl);
        }

        std.sort.block(VisualLabel, visualLabels.items, {}, compareVisualLabels);

        const ul = try Renderer.buildUnderlineLanes(visualLabels.items, alloc);

        for (ul) |lane| {
            try self.renderBorderPrefix(padding);

            var currentCol: usize = 0;

            var occupiedCols: std.ArrayList(u1) = .empty;
            try occupiedCols.resize(alloc, lane.endCol);
            std.debug.print("occupied cols len: {d}\n", .{occupiedCols.items.len});

            for (lane.labels.items) |label| {
                const color = self.getLabelColor(diagnostic, label.label);
                const underlineChar = self.getLabelUnderline(label.label);
                try self.renderUnderline(&currentCol, label.startCol, label.width, underlineChar, color);
                @memset(occupiedCols.items[label.startCol..label.endCol], 1);
            }
            std.debug.print("Occupied cols: {any}\n", .{occupiedCols.items});
            try self.resetColor();

            var allLabelsFitOnLine = true;

            for (0..lane.labels.items.len) |i| {
                const label = lane.labels.items[lane.labels.items.len - 1 - i];
                const messageStart = label.endCol + 1;
                const messageEnd = messageStart + sf.displayWidth(label.label.message, 0, label.label.message.len);

                var isFree = true;
                for (messageStart..messageEnd) |col| {
                    if (col < occupiedCols.items.len and occupiedCols.items[col] == 1) {
                        isFree = false;
                        allLabelsFitOnLine = false;
                        break;
                    }
                }

                if (isFree) {
                    try occupiedCols.resize(alloc, messageEnd);
                    @memset(occupiedCols.items[messageStart..messageEnd], 1);
                }

                std.debug.print("Placing message for label '{s}' at col {d}. isFree = {any}\n", .{ label.label.message, messageStart, isFree });
                std.debug.print("Occupied cols after placing message: {any}\n", .{occupiedCols.items});
            }
            std.debug.print("**All labels fit on line: {any}\n", .{allLabelsFitOnLine});

            if (allLabelsFitOnLine) {
                for (lane.labels.items) |label| {
                    const messageStart = label.endCol + 1;
                    try self.renderSpacesTo(&currentCol, messageStart);
                    try self.setColor(self.getLabelColor(diagnostic, label.label));
                    try self.writer.print("{s}", .{label.label.message});
                }
            }
            try self.writer.print("\n", .{});
        }

        // for (visualLabels.items) |vl| {
        //     std.debug.print("Visual label: {s} [{d}, {d})\n", .{ vl.label.message, vl.startCol, vl.endCol });
        //     try self.renderPadding(padding);
        //     try self.setColor(self.config.colors.border);
        //     try self.writer.print("{s} ", .{self.config.charset.border});
        //     try self.renderPadding(vl.startCol);
        //     try self.setColor(self.getLabelColor(diagnostic, vl.label));
        //     // for (0..vl.width) |_| try self.writer.print("{s}", .{self.getLabelUnderline(vl.label)});
        //     try self.renderUnderline(vl.label, vl.width);
        //     try self.writer.print(" {s}\n", .{vl.label.message});
        // }

        // for (labeledLine.labels) |label| {
        //     const labelStartDisplayCol = sf.displayCol(source.source, lineRange.start, label.start);
        //     const labelDisplayWidth = sf.displayWidth(source.source, label.start, label.end);
        //     try self.renderPadding(padding);
        //     try self.setColor(self.config.colors.border);
        //     try self.writer.print("{s} ", .{self.config.charset.border});
        //     try self.renderPadding(labelStartDisplayCol);
        //     try self.setColor(self.getLabelColor(diagnostic, label));
        //     for (0..labelDisplayWidth) |_|
        //         try self.writer.print("{s}", .{self.getLabelUnderline(label)});
        //     try self.writer.print(" {s}\n", .{label.message});
        // }
    }

    fn renderSpacesTo(self: *Renderer, currentCol: *usize, targetCol: usize) !void {
        while (currentCol.* < targetCol) : (currentCol.* += 1) {
            try self.writer.print("+", .{});
        }
    }

    fn renderUnderline(
        self: *Renderer,
        currentCol: *usize,
        startCol: usize,
        width: usize,
        underline: []const u8,
        color: std.io.tty.Color,
    ) !void {
        std.debug.print("Rendering underline from col {d} to col {d} with width {d}. currentcol = {d}\n", .{
            startCol,
            startCol + width,
            width,
            currentCol.*,
        });
        try self.renderSpacesTo(currentCol, startCol);
        std.debug.print("After rendering spaces, currentcol = {d}\n", .{currentCol.*});

        try self.setColor(color);
        for (0..width) |_| {
            try self.writer.print("{s}", .{underline});
        }
        try self.resetColor();

        currentCol.* = startCol + width;
    }
    fn setColor(self: *const Renderer, color: std.io.tty.Color) !void {
        try std.io.tty.Config.setColor(self.config.colorMode, self.writer, color);
    }

    fn resetColor(self: *const Renderer) !void {
        try std.io.tty.Config.setColor(self.config.colorMode, self.writer, .reset);
    }

    fn renderMainMessage(self: *Renderer, diagnostic: Diagnostic) !void {
        const color = self.config.colors.header(diagnostic.severity);
        try self.setColor(color);
        try self.setColor(.bold);
        try self.writer.print("{s}", .{@tagName(diagnostic.severity)});
        try self.resetColor();
        try self.writer.print(": {s}\n", .{diagnostic.message});
    }

    fn renderFileHeader(self: *Renderer, fileName: []const u8, lineCol: LineCol, padding: usize) !void {
        try self.renderPadding(padding);

        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}", .{self.config.charset.headerStart});
        try self.writer.print("[ ", .{});
        try self.resetColor();

        try self.renderFileLocation(fileName, lineCol);
        try self.setColor(self.config.colors.border);
        try self.writer.print(" ]", .{});
        try self.resetColor();
        try self.writer.print("\n", .{});
        // try self.renderEmptyBorderLine(padding);
    }

    /// Renders a line with just the border character, appended a new line.
    fn renderEmptyBorderLine(self: *const Renderer, padding: usize) !void {
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}", .{self.config.charset.border});
        try self.resetColor();
        try self.writer.print("\n", .{});
    }

    fn renderBorderBreak(self: *const Renderer, padding: usize) !void {
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}\n", .{self.config.charset.borderBreak});
        try self.resetColor();
    }

    fn renderFileLocation(self: *const Renderer, fileName: []const u8, startLoc: LineCol) !void {
        try self.writer.print("{s}:{f}", .{ fileName, startLoc });
    }

    fn renderPadding(self: *const Renderer, padding: usize) !void {
        for (0..padding) |_| try self.writer.print(" ", .{});
    }

    fn getLabelColor(self: *const Renderer, diagnostic: Diagnostic, label: Label) std.io.tty.Color {
        return switch (label.style) {
            .Primary => self.config.colors.header(diagnostic.severity),
            .Secondary => self.config.colors.secondaryLabel,
        };
    }

    fn getLabelUnderline(self: *const Renderer, label: Label) []const u8 {
        return switch (label.style) {
            .Primary => self.config.charset.primaryUnderline,
            .Secondary => self.config.charset.secondaryUnderline,
        };
    }
};

fn findFirstLabelLineCol(labels: []const Label, sourceFiles: []const SourceFile) LineCol {
    const file = sourceFiles[labels[0].fileId]; // FIXME: temporary single file assumption
    var earliest = file.lineCol(labels[0].start) catch LineCol{
        .line = std.math.maxInt(usize),
        .col = std.math.maxInt(usize),
    };

    for (labels) |label| {
        const lc = file.lineCol(label.start) catch continue;
        if (lc.line < earliest.line or (lc.line == earliest.line and lc.col < earliest.col)) {
            earliest = lc;
        }
    }
    return earliest;
}

fn findLargestLineNumber(labeledFiles: []const LabeledFile) usize {
    var largest: usize = 0;
    for (labeledFiles) |file| {
        for (file.lines) |line| {
            if (line.number > largest) largest = line.number;
        }
    }
    return largest;
}
