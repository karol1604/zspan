const std = @import("std");

const Config = @import("config.zig").Config;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Label = @import("diagnostic.zig").Label;
const LineCol = @import("utils.zig").LineCol;
const SourceFile = @import("sourcefile.zig").SourceFile;
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

fn buildLabeledFiles(labels: []const Label, sources: []const SourceFile, alloc: std.mem.Allocator) ![]LabeledFile {
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
                const lineRange = labeledLine.range;
                const line = source.source[lineRange.start..lineRange.end];
                try self.renderPadding(padding - utils.digitCount(labeledLine.number) - 1);
                try self.setColor(self.config.colors.border);
                try self.writer.print("{d} {s} ", .{ labeledLine.number, self.config.charset.border });
                try self.resetColor();
                try self.writer.print("{s}\n", .{line});

                for (labeledLine.labels) |label| {
                    const labelStartCol = (try source.lineCol(label.start)).col;
                    try self.renderPadding(padding);
                    try self.setColor(self.config.colors.border);
                    try self.writer.print("{s} ", .{self.config.charset.border});
                    try self.renderPadding(labelStartCol - 1);
                    try self.setColor(self.getLabelColor(diagnostic, label));
                    for (0..(label.end - label.start)) |_|
                        try self.writer.print("{s}", .{self.getLabelUnderline(label)});
                    try self.writer.print(" {s}\n", .{label.message});
                }

                // try self.renderEmptyBorderLine(padding);

                const nextLineNum = if (idx + 1 < labeledFile.lines.len) labeledFile.lines[idx + 1].number else labeledLine.number;
                //
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
