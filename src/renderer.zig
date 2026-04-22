const std = @import("std");
const Config = @import("config.zig").Config;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const SourceFile = @import("sourcefile.zig").SourceFile;
const LineCol = @import("utils.zig").LineCol;
const Label = @import("diagnostic.zig").Label;
const utils = @import("utils.zig");

const BOLD = "\x1b[1m";

pub const Renderer = struct {
    config: Config,
    writer: *std.io.Writer,

    pub fn init(config: Config, writer: *std.io.Writer) Renderer {
        return .{
            .config = config,
            .writer = writer,
        };
    }

    pub fn renderDiagnostic(self: *Renderer, diagnostic: Diagnostic, sourceFiles: []const SourceFile) !void {
        const sourceFile = sourceFiles[diagnostic.labels[0].fileId]; // FIXME: temporary single file assumption

        try self.renderMainMessage(diagnostic);

        const padding = utils.digitCount(findLargestLineNumber(diagnostic.labels, sourceFiles)) + 1; // +1 for the space after the line number

        // NOTE: for now, we only have one source file but eventually we will want to group labels by file and render them together
        try self.renderFileHeader(sourceFile.name, findFirstLabelLineCol(diagnostic.labels, sourceFiles), padding);
        try self.renderEmptyBorderLine(padding);

        // v1 will be stupid simple one line per label and one label per line
        for (diagnostic.labels, 0..) |label, idx| {
            const file = sourceFiles[label.fileId];
            const lineCol = file.lineCol(label.start) catch continue;
            try self.renderPadding(padding - utils.digitCount(lineCol.line) - 1);
            try self.setColor(self.config.colors.border);
            try self.writer.print("{d} {s} ", .{ lineCol.line, self.config.charset.border });
            try self.resetColor();

            const lineRange = file.lineRange(label.start) catch continue;
            const line = file.source[lineRange.start..lineRange.end];
            try self.writer.print("{s}\n", .{line});

            try self.renderPadding(padding);
            try self.setColor(self.config.colors.border);
            try self.writer.print("{s} ", .{self.config.charset.border});

            try self.renderPadding(lineCol.col - 1);
            try self.setColor(self.getLabelColor(diagnostic, label));
            for (0..(label.end - label.start)) |_|
                try self.writer.print("{s}", .{self.getLabelUnderline(label)});
            try self.writer.print(" {s}\n", .{label.message});

            var nextLineCol = lineCol;
            if (idx + 1 < diagnostic.labels.len)
                nextLineCol = try file.lineCol(diagnostic.labels[idx + 1].start);

            // NOTE: should we keep this?
            if (nextLineCol.line - lineCol.line > 1) {
                try self.renderBorderBreak(padding);
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

fn findLargestLineNumber(labels: []const Label, sourceFiles: []const SourceFile) usize {
    const file = sourceFiles[labels[0].fileId]; // FIXME: temporary single file assumption
    var largest: usize = 0;
    for (labels) |label| {
        const lineCol = file.lineCol(label.end) catch continue;
        const line = lineCol.line;
        if (line > largest) {
            largest = line;
        }
    }
    return largest;
}
