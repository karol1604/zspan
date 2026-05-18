const std = @import("std");

const Config = @import("config.zig").Config;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Label = @import("diagnostic.zig").Label;
const LineCol = @import("utils.zig").LineCol;
const sf = @import("sourcefile.zig");
const SourceFile = sf.SourceFile;
const utils = @import("utils.zig");

const LabelFragmentKind = enum {
    SingleLine,
    MultiStart,
    MultiMiddle,
    MultiEnd,
};
const LabelFragment = struct {
    label: Label,
    kind: LabelFragmentKind,
    start: usize, // byte offset of the start of this fragment
    end: usize, // byte offset of the end of this fragment
    // anchorCol: usize, // column where connector will be rendered for multi-line labels
    showMessage: bool,
};

const LabeledLine = struct {
    number: usize, // 1-indexed
    range: utils.Range, // byte range
    // labels: []const Label, // labels that apply to this line
    fragments: []const LabelFragment, // fragments of labels that apply to this line
};

const LabeledFile = struct {
    fileId: usize,
    lines: []LabeledLine, // lines should be sorted by line number
};

const LabeledLineBuilder = struct {
    number: usize,
    range: utils.Range,
    fragments: std.ArrayList(LabelFragment),
};

const LabeledFileBuilder = struct {
    file_id: usize,
    lines: std.ArrayList(LabeledLineBuilder),
};

const VisualLabel = struct {
    label: Label,
    startCol: usize,
    endCol: usize,
    sourceStartCol: usize,
    sourceEndCol: usize,
    width: usize, // at least 1
    anchorCol: usize, // col where connector will be renderer
    lane: usize = 0,
    fragmentKind: LabelFragmentKind,
};

const UnderlineLane = struct {
    labels: std.ArrayList(VisualLabel),
    endCol: usize,
};

const RowKind = enum {
    Underline,
    Message,
    Connector,
};

const RowSegment = struct {
    kind: RowKind,
    startCol: usize,
    width: usize,
    text: []const u8,
    color: std.Io.Terminal.Color,

    pub fn format(self: RowSegment, writer: *std.io.Writer) !void {
        try writer.print("{{\n", .{});
        try writer.print("  kind: {s},\n", .{@tagName(self.kind)});
        try writer.print("  startCol: {d},\n", .{self.startCol});
        try writer.print("  width: {d},\n", .{self.width});
        try writer.print("  text: {s},\n", .{self.text});
        try writer.print("  color: {s},\n", .{@tagName(self.color)});
        try writer.print("}}\n", .{});
    }
};

const Span = struct {
    start: usize,
    end: usize,
};

const LanePlan = struct {
    row: []const RowSegment,
    deferredLabels: []const VisualLabel,
};

fn spansOverlap(a: Span, b: Span) bool {
    return a.start < b.end and b.start < a.end;
}

fn underlineSpan(label: VisualLabel) Span {
    return Span{
        .start = label.startCol,
        .end = label.endCol,
    };
}

fn messageDisplayWidth(message: []const u8) usize {
    return sf.displayWidth(message, 0, message.len);
}

fn messageSpan(label: VisualLabel) Span {
    const start = label.endCol + 1;
    const width = messageDisplayWidth(label.label.message);
    return Span{
        .start = start,
        .end = start + width,
    };
}

fn laneCanInlineMessages(labels: []const VisualLabel) bool {
    for (labels, 0..) |label, i| {
        if (label.label.message.len == 0) continue;

        const message = messageSpan(label);
        for (labels) |otherLabel| {
            if (spansOverlap(message, underlineSpan(otherLabel))) {
                return false;
            }
        }

        for (labels[i + 1 ..]) |otherLabel| {
            if (otherLabel.label.message.len == 0) continue;
            if (spansOverlap(message, messageSpan(otherLabel))) {
                return false;
            }
        }
    }
    return true;
}

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
        .fragments = .empty,
    });
    return &lines.items[lines.items.len - 1];
}

fn compareFragmentsByStart(_: void, a: LabelFragment, b: LabelFragment) bool {
    if (a.start != b.start) return a.start < b.start;
    return a.end > b.end;
}

fn makeFragment(
    label: Label,
    effectiveEnd: usize,
    lineRange: utils.Range,
    lineIdx: usize,
    startLineIdx: usize,
    endLineIdx: usize,
) LabelFragment {
    const isSingleLine = startLineIdx == endLineIdx;
    const isStart = lineIdx == startLineIdx;
    const isEnd = lineIdx == endLineIdx;

    const kind: LabelFragmentKind = if (isSingleLine)
        .SingleLine
    else if (isStart)
        .MultiStart
    else if (isEnd)
        .MultiEnd
    else
        .MultiMiddle;

    const fragmentStart = if (isStart) label.start else lineRange.start;
    const fragmentEnd = if (isEnd) effectiveEnd else lineRange.end;

    return LabelFragment{
        .label = label,
        .kind = kind,
        .start = fragmentStart,
        .end = fragmentEnd,
        .showMessage = isEnd, // only show message on the last fragment of a multi-line label
    };
}

fn buildLabeledFiles(
    labels: []const Label,
    sources: []const SourceFile,
    alloc: std.mem.Allocator,
) ![]LabeledFile {
    var fileBuilders: std.ArrayList(LabeledFileBuilder) = .empty;

    for (labels) |label| {
        const source = sources[label.fileId];
        // ensure at least 1 char is highlighted even for zero-length labels
        const effectiveEnd = if (label.end > label.start) label.end else label.start + 1;
        const startLineIdx = try source.lineIndexAt(label.start);
        const endLineIdx = try source.lineIndexAt(effectiveEnd - 1);

        const fileBuilder = try findOrCreateLabeledFile(&fileBuilders, label.fileId, alloc);

        var lineIdx: usize = startLineIdx;
        while (lineIdx <= endLineIdx) : (lineIdx += 1) {
            const lineRange = try source.lineRangeAtIndex(lineIdx);
            const lineNumber = lineIdx + 1;

            const fragment = makeFragment(label, effectiveEnd, lineRange, lineIdx, startLineIdx, endLineIdx);

            const lineBuilder = try findOrCreateLabeledLine(
                &fileBuilder.lines,
                lineNumber,
                lineRange,
                alloc,
            );
            try lineBuilder.fragments.append(alloc, fragment);
        }
    }

    var files: std.ArrayList(LabeledFile) = .empty;
    for (fileBuilders.items) |*fileBuilder| {
        std.sort.block(LabeledLineBuilder, fileBuilder.lines.items, {}, compareLabeledLines);

        for (fileBuilder.lines.items) |*lineBuilder| {
            std.sort.block(LabelFragment, lineBuilder.fragments.items, {}, compareFragmentsByStart);
        }

        var lines: std.ArrayList(LabeledLine) = .empty;
        for (fileBuilder.lines.items) |*lineBuilder| {
            try lines.append(alloc, .{
                .number = lineBuilder.number,
                .range = lineBuilder.range,
                // .labels = try lineBuilder.labels.toOwnedSlice(alloc),
                .fragments = try lineBuilder.fragments.toOwnedSlice(alloc),
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
    writer: *std.Io.Writer,

    pub fn init(config: Config, writer: *std.Io.Writer) Renderer {
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
            // NOTE: here
            const firstLabel = firstLine.fragments[0].label;
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

    fn buildUnderlineLanes(_: *Renderer, labels: []VisualLabel, alloc: std.mem.Allocator) ![]UnderlineLane {
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

    fn multilineMarkerForLine(
        self: *const Renderer,
        source: SourceFile,
        labeledLine: LabeledLine,
    ) ?[]const u8 {
        for (labeledLine.fragments) |fragment| {
            switch (fragment.kind) {
                .MultiStart => {
                    const startCol = sf.displayCol(
                        source.source,
                        labeledLine.range.start,
                        fragment.start,
                    );

                    if (startCol == 0) {
                        return self.config.charset.multiTopLeft;
                    }

                    return null;
                },
                .MultiMiddle, .MultiEnd => return self.config.charset.multiLeft,
                .SingleLine => {},
            }
        }

        return null;
    }

    fn renderSourceLine(
        self: *Renderer,
        source: SourceFile,
        diagnostic: Diagnostic,
        labeledLine: LabeledLine,
        padding: usize,
        alloc: std.mem.Allocator,
    ) !void {
        var primaryFragments: std.ArrayList(LabelFragment) = .empty;

        for (labeledLine.fragments) |fragment| {
            if (fragment.label.style == .Primary) {
                try primaryFragments.append(alloc, fragment);
            }
        }
        std.sort.block(LabelFragment, primaryFragments.items, {}, compareFragmentsByStart);

        const lineRange = labeledLine.range;
        const line = source.source[lineRange.start..lineRange.end];
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{d} {s} ", .{ labeledLine.number, self.config.charset.border });
        try self.resetColor();

        const multilineMarker = self.multilineMarkerForLine(source, labeledLine);

        if (multilineMarker) |marker| {
            const color = switch (primaryFragments.items.len) {
                0 => self.config.colors.border,
                else => self.config.colors.primaryLabelError,
            };
            try self.setColor(color);
            try self.writer.print("{s} ", .{marker});
            try self.resetColor();
        }

        if (primaryFragments.items.len == 0) {
            try self.writer.print("{s}\n", .{line});
            return;
        }

        try self.writer.print("{s}", .{source.source[lineRange.start..primaryFragments.items[0].start]});

        var currentByte = primaryFragments.items[0].start;
        for (primaryFragments.items, 0..) |fragment, i| {
            const col = self.getLabelColor(diagnostic, fragment.label);
            try self.setColor(col);
            try self.writer.print("{s}", .{source.source[fragment.start..fragment.end]});
            try self.resetColor();

            currentByte = fragment.end;

            const nextStart = if (i + 1 < primaryFragments.items.len)
                primaryFragments.items[i + 1].start
            else
                lineRange.end;

            if (currentByte < nextStart) {
                try self.writer.print("{s}", .{source.source[currentByte..nextStart]});
                currentByte = nextStart;
            }
        }
        try self.writer.print("\n", .{});
    }

    fn buildVisualLabels(
        self: *Renderer,
        source: SourceFile,
        labeledLine: LabeledLine,
        alloc: std.mem.Allocator,
    ) ![]VisualLabel {
        var visualLabels: std.ArrayList(VisualLabel) = .empty;

        // account for multiline marker taking up space
        const multilineMarker = self.multilineMarkerForLine(source, labeledLine);
        const sourceColOffset: usize = if (multilineMarker != null) 2 else 0;

        for (labeledLine.fragments) |fragment| {
            const startCol = sf.displayCol(source.source, labeledLine.range.start, fragment.start);
            const width = @max(1, sf.displayWidth(source.source, fragment.start, fragment.end));
            const endCol = startCol + width;

            var label = fragment.label;
            if (!fragment.showMessage) {
                label.message = "";
            }

            const vl = VisualLabel{
                .label = label,
                .startCol = startCol + sourceColOffset,
                .endCol = endCol + sourceColOffset,
                .sourceStartCol = startCol,
                .sourceEndCol = endCol,
                .width = width,
                .anchorCol = startCol + sourceColOffset,
                .fragmentKind = fragment.kind,
            };
            try visualLabels.append(alloc, vl);
        }

        return try visualLabels.toOwnedSlice(alloc);
    }

    fn planLaneRow(
        self: *Renderer,
        diagnostic: Diagnostic,
        lane: UnderlineLane,
        alloc: std.mem.Allocator,
    ) !LanePlan {
        var segments: std.ArrayList(RowSegment) = .empty;
        const canInline = laneCanInlineMessages(lane.labels.items);
        var deferredLabels: std.ArrayList(VisualLabel) = .empty;

        for (lane.labels.items) |label| {
            const color = self.getLabelColor(diagnostic, label.label);
            const underlineChar = self.getLabelUnderline(label.label);

            if (label.fragmentKind == .SingleLine) {
                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = label.startCol,
                    .width = label.width,
                    .text = underlineChar,
                    .color = color,
                });
            }

            if (label.fragmentKind == .MultiStart and label.sourceStartCol > 0) {
                // std.debug.print("Adding multi-line start underline for label at col {d} with message '{s}'\n", .{
                //     label.startCol,
                //     label.label.message,
                // });
                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = 0,
                    .width = 1,
                    .text = self.config.charset.multiTopLeft,
                    .color = color,
                });

                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = 1,
                    .width = label.startCol - 1,
                    .text = self.config.charset.multiHorizontal,
                    .color = color,
                });

                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = label.startCol,
                    .width = 1,
                    .text = self.config.charset.multiMarker,
                    .color = color,
                });
            }

            if (label.fragmentKind == .MultiEnd) {
                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = 0,
                    .width = 1,
                    .text = self.config.charset.multiBottomLeft,
                    .color = color,
                });

                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = 1,
                    .width = label.endCol - 1,
                    .text = self.config.charset.multiHorizontal,
                    .color = color,
                });

                try segments.append(alloc, .{
                    .kind = .Underline,
                    .startCol = label.endCol,
                    .width = 1,
                    .text = self.config.charset.multiMarker,
                    .color = color,
                });
            }

            const messageStartCol = if (label.fragmentKind == .MultiEnd)
                label.endCol + 2
            else
                label.endCol + 1;

            if (canInline and label.label.message.len > 0) {
                try segments.append(alloc, .{
                    .kind = .Message,
                    .startCol = messageStartCol,
                    .width = messageDisplayWidth(label.label.message),
                    .text = label.label.message,
                    .color = color,
                });
            } else if (label.label.message.len > 0) {
                try deferredLabels.append(alloc, label);
            }
        }

        std.sort.block(RowSegment, segments.items, {}, compareRowSegments);
        // std.sort.block(VisualLabel, deferredLabels.items, {}, compareVisualLabelsByAnchorDesc);

        // std.debug.print("deffered labels len: {d}\n", .{deferredLabels.items.len});
        // for (deferredLabels.items) |label| {
        //     std.debug.print("Adding connector for label at col {d} with message '{s}'\n", .{
        //         label.startCol,
        //         label.label.message,
        //     });
        // }

        return LanePlan{
            .row = try segments.toOwnedSlice(alloc),
            .deferredLabels = try deferredLabels.toOwnedSlice(alloc),
        };
    }

    fn compareVisualLabelsByAnchorDesc(_: void, a: VisualLabel, b: VisualLabel) bool {
        if (a.anchorCol != b.anchorCol) return a.anchorCol > b.anchorCol;

        const aLen = a.endCol - a.startCol;
        const bLen = b.endCol - b.startCol;

        if (aLen != bLen) return aLen > bLen;

        if (a.label.style != b.label.style) {
            return a.label.style == .Primary;
        }

        return false;
    }

    fn compareVisualLabelsByAnchorAsc(_: void, a: VisualLabel, b: VisualLabel) bool {
        if (a.anchorCol != b.anchorCol) return a.anchorCol < b.anchorCol;

        const aLen = a.endCol - a.startCol;
        const bLen = b.endCol - b.startCol;

        if (aLen != bLen) return aLen > bLen;

        if (a.label.style != b.label.style) {
            return a.label.style == .Primary;
        }

        return false;
    }

    fn planConnectorGuideRow(
        self: *Renderer,
        diagnostic: Diagnostic,
        labels: []const VisualLabel,
        alloc: std.mem.Allocator,
    ) ![]const RowSegment {
        var segments: std.ArrayList(RowSegment) = .empty;

        var lastAnchor: ?usize = null;

        for (labels) |label| {
            if (lastAnchor != null and lastAnchor.? == label.anchorCol) {
                continue;
            }

            lastAnchor = label.anchorCol;

            try segments.append(alloc, .{
                .kind = .Connector,
                .startCol = label.anchorCol,
                .width = 1,
                .text = self.config.charset.connector,
                .color = self.getLabelColor(diagnostic, label.label),
            });
        }

        return try segments.toOwnedSlice(alloc);
    }

    fn planConnectorMessageRows(
        self: *Renderer,
        diagnostic: Diagnostic,
        labelsDesc: []const VisualLabel,
        alloc: std.mem.Allocator,
    ) ![]const []const RowSegment {
        var rows: std.ArrayList([]const RowSegment) = .empty;

        for (labelsDesc, 0..) |current, i| {
            var segments: std.ArrayList(RowSegment) = .empty;

            const remaining = labelsDesc[i + 1 ..];

            var lastConnectorAnchor: ?usize = null;

            for (remaining) |other| {
                if (other.anchorCol >= current.anchorCol) {
                    continue;
                }

                if (lastConnectorAnchor != null and lastConnectorAnchor.? == other.anchorCol) {
                    continue;
                }

                lastConnectorAnchor = other.anchorCol;

                try segments.append(alloc, .{
                    .kind = .Connector,
                    .startCol = other.anchorCol,
                    .width = 1,
                    .text = self.config.charset.connector,
                    .color = self.getLabelColor(diagnostic, other.label),
                });
            }

            try segments.append(alloc, .{
                .kind = .Message,
                .startCol = current.anchorCol,
                .width = messageDisplayWidth(current.label.message),
                .text = current.label.message,
                .color = self.getLabelColor(diagnostic, current.label),
            });

            std.sort.block(RowSegment, segments.items, {}, compareRowSegments);

            try rows.append(alloc, try segments.toOwnedSlice(alloc));
        }

        return try rows.toOwnedSlice(alloc);
    }

    fn planAnnotationRows(
        self: *Renderer,
        diagnostic: Diagnostic,
        lanes: []UnderlineLane,
        alloc: std.mem.Allocator,
    ) ![]const []const RowSegment {
        var rows: std.ArrayList([]const RowSegment) = .empty;
        var deferredLabels: std.ArrayList(VisualLabel) = .empty;

        for (lanes) |lane| {
            const lanePlan = try self.planLaneRow(diagnostic, lane, alloc);
            if (lanePlan.row.len > 0)
                try rows.append(alloc, lanePlan.row);
            try deferredLabels.appendSlice(alloc, lanePlan.deferredLabels);
        }

        if (deferredLabels.items.len == 0) {
            return try rows.toOwnedSlice(alloc);
        }

        std.sort.block(VisualLabel, deferredLabels.items, {}, compareVisualLabelsByAnchorAsc);

        const guideRow = try self.planConnectorGuideRow(
            diagnostic,
            deferredLabels.items,
            alloc,
        );

        try rows.append(alloc, guideRow);

        std.sort.block(
            VisualLabel,
            deferredLabels.items,
            {},
            compareVisualLabelsByAnchorDesc,
        );

        const messageRows = try self.planConnectorMessageRows(
            diagnostic,
            deferredLabels.items,
            alloc,
        );

        try rows.appendSlice(alloc, messageRows);

        return try rows.toOwnedSlice(alloc);
    }

    fn renderRowSegments(self: *Renderer, padding: usize, segments: []const RowSegment) !void {
        try self.renderBorderPrefix(padding);

        var currentCol: usize = 0;

        for (segments) |segment| {
            try self.renderSpacesTo(&currentCol, segment.startCol);
            try self.setColor(segment.color);

            switch (segment.kind) {
                .Underline, .Connector => {
                    for (0..segment.width) |_| {
                        try self.writer.print("{s}", .{segment.text});
                    }
                },
                .Message => {
                    try self.writer.print("{s}", .{segment.text});
                },
            }
            try self.resetColor();
            currentCol = segment.startCol + segment.width;
        }
        try self.writer.print("\n", .{});
    }

    fn renderLabeledSourceLine(
        self: *Renderer,
        diagnostic: Diagnostic,
        source: SourceFile,
        labeledLine: LabeledLine,
        padding: usize,
        alloc: std.mem.Allocator,
    ) !void {
        try self.renderSourceLine(
            source,
            diagnostic,
            labeledLine,
            padding - utils.digitCount(labeledLine.number) - 1,
            alloc,
        );

        const visualLabels = try self.buildVisualLabels(source, labeledLine, alloc);
        std.sort.block(VisualLabel, visualLabels, {}, compareVisualLabels);

        const ul = try self.buildUnderlineLanes(visualLabels, alloc);

        const rows = try self.planAnnotationRows(diagnostic, ul, alloc);
        for (rows) |row| {
            try self.renderRowSegments(padding, row);
        }
    }

    fn compareRowSegments(_: void, a: RowSegment, b: RowSegment) bool {
        if (a.startCol != b.startCol) return a.startCol < b.startCol;

        // underlines should render before messages if they somehow have same start
        return @intFromEnum(a.kind) < @intFromEnum(b.kind);
    }

    fn renderSpacesTo(self: *Renderer, currentCol: *usize, targetCol: usize) !void {
        while (currentCol.* < targetCol) : (currentCol.* += 1) {
            try self.writer.print(" ", .{});
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
        // std.debug.print("Rendering underline from col {d} to col {d} with width {d}. currentcol = {d}\n", .{
        //     startCol,
        //     startCol + width,
        //     width,
        //     currentCol.*,
        // });
        try self.renderSpacesTo(currentCol, startCol);
        // std.debug.print("After rendering spaces, currentcol = {d}\n", .{currentCol.*});

        try self.setColor(color);
        for (0..width) |_| {
            try self.writer.print("{s}", .{underline});
        }
        try self.resetColor();

        currentCol.* = startCol + width;
    }
    fn setColor(self: *const Renderer, color: std.Io.Terminal.Color) !void {
        const terminal: std.Io.Terminal = .{
            .mode = self.config.colorMode,
            .writer = self.writer,
        };
        try terminal.setColor(color);
    }

    fn resetColor(self: *const Renderer) !void {
        const terminal: std.Io.Terminal = .{
            .mode = self.config.colorMode,
            .writer = self.writer,
        };
        try terminal.setColor(.reset);
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

    fn getLabelColor(self: *const Renderer, diagnostic: Diagnostic, label: Label) std.Io.Terminal.Color {
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
