const std = @import("std");
const Config = @import("config.zig").Config;
const Severity = @import("diagnostic.zig").Severity;
const Label = @import("diagnostic.zig").Label;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const SourceFiles = @import("source-file.zig").SourceFiles;
const SourceFile = @import("source-file.zig").SourceFile;
const LineCol = @import("utils.zig").LineCol;
const getDigitsLength = @import("utils.zig").getDigitsLength;
const OrderedMap = @import("utils.zig").OrderedMap;
const utils = @import("utils.zig");
const Range = utils.Range;

const Line = struct {
    number: usize,
    range: Range,
    labels: std.ArrayList(Label),
};

const LabeledFile = struct {
    fileId: usize,
    name: []const u8,
    start: usize,
    location: LineCol,
    lines: OrderedMap(usize, Line),
};

pub const Renderer = struct {
    config: Config,
    writer: std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter, config: Config) Renderer {
        return .{
            .writer = writer,
            .config = config,
        };
    }

    fn setColor(self: *const Renderer, color: std.io.tty.Color) !void {
        try std.io.tty.Config.setColor(self.config.colorMode, self.writer, color);
    }

    fn resetColor(self: *const Renderer) !void {
        try std.io.tty.Config.setColor(self.config.colorMode, self.writer, .reset);
    }

    pub fn renderMinimalDiagnostic(self: *const Renderer, diagnostic: *const Diagnostic, sourceFiles: *const SourceFiles) !void {
        for (diagnostic.labels.items) |label| {
            try self.renderMainMessage(
                true,
                diagnostic.severity,
                diagnostic.message,
                try sourceFiles.name(label.fileId),
                try sourceFiles.location(label.fileId, label.start),
            );
        }
    }

    pub fn renderVerboseDiagnostic(self: *const Renderer, diagnostic: *const Diagnostic, sourceFiles: *const SourceFiles) !void {
        try self.renderMainMessage(
            false,
            diagnostic.severity,
            diagnostic.message,
            try sourceFiles.name(diagnostic.labels.items[0].fileId),
            try sourceFiles.location(diagnostic.labels.items[0].fileId, diagnostic.labels.items[0].start),
        );

        var labeledFiles = std.ArrayList(LabeledFile).init(diagnostic.alloc);

        var padding: usize = 0;

        for (diagnostic.labels.items) |label| {
            const startLineIdx = try sourceFiles.lineIndex(label.fileId, label.start);
            const startLineNum: usize = startLineIdx + 1; // Lines are 1-indexed
            const startLineRange = try sourceFiles.lineRange(label.fileId, label.start);

            const endLineIdx = try sourceFiles.lineIndex(label.fileId, label.end);
            const endLineNum: usize = endLineIdx + 1; // Lines are 1-indexed

            padding = @max(padding, getDigitsLength(startLineNum));
            padding = @max(padding, getDigitsLength(endLineNum));

            var lf = LabeledFile{
                .fileId = label.fileId,
                .name = try sourceFiles.name(label.fileId),
                .start = label.start,
                .location = try sourceFiles.location(label.fileId, label.start),
                // TODO: find a better upper bound for the number of lines
                .lines = OrderedMap(usize, Line).init(diagnostic.alloc),
            };

            // NOTE: im sure there is a better way to do this
            var found = false;
            var idx: usize = 0;
            for (labeledFiles.items, 0..) |*existingFile, i| {
                if (existingFile.fileId == lf.fileId) {
                    // If the file is already in the list, skip adding it again
                    found = true;
                    if (existingFile.start > lf.start) {
                        std.debug.print("Updating existing file: {s}\n", .{lf.name});
                        existingFile.start = lf.start;
                        existingFile.location = lf.location;
                        lf = existingFile.*; // NOTE: useless line
                        idx = i;
                    }
                    break;
                }
            }

            std.debug.print("Found labeled file: {s}\n", .{lf.location});

            if (!found) {
                try labeledFiles.append(lf);
                idx = labeledFiles.items.len - 1;
            }

            var labeledFile = &labeledFiles.items[idx];
            if (startLineIdx == endLineIdx) {
                std.debug.print("------ Single line label: {s}:{d}\n", .{ lf.name, startLineNum });
                // const labelStartCol = try sourceFiles.location(label.fileId, label.start);
                var line = try labeledFile.lines.insert(startLineIdx, Line{
                    .number = startLineNum,
                    .range = startLineRange,
                    .labels = std.ArrayList(Label).init(diagnostic.alloc),
                });

                std.debug.print("Inserting line: {any}\n", .{line.number});
                try line.labels.append(label);
            }

            // if (startLineIdx == endLineIdx) {
            //     std.debug.print("------ Single line label: {s}:{d}\n", .{ labeledFile.name, startLineNum });
            //     // const labelStartCol = try sourceFiles.location(label.fileId, label.start);
            //     try labeledFile.lines.insert(startLineIdx, (try sourceFiles.location(label.fileId, label.start)).col);
            // }

            // std.debug.print("Lines: {any}\n", .{labeledFile.lines.items.items});
        }

        // std.debug.print("labeledFiles: {any}\n", .{labeledFiles.items[0].lines.items.items[0]});
        std.debug.print("labeledFiles: {any}\n", .{labeledFiles.items[0].location});

        std.debug.print("--------------------\n", .{});
        for (labeledFiles.items) |labeledFile| {
            try self.renderFileStart(
                labeledFile.name,
                labeledFile.location,
                padding + 1,
            );

            for (labeledFile.lines.items.items) |line| {
                try self.renderLineNumber(line.value.number, padding);
                try self.setColor(self.config.colors.border);
                try self.writer.print("{s}", .{self.config.charset.border});
                try self.writer.print(" ", .{});
                try self.resetColor();

                try self.writer.print("{s}\n", .{(try sourceFiles.source(labeledFile.fileId))[line.value.range.start..line.value.range.end]});
                try self.renderEmptyBorderLine(padding + 1);
                std.debug.print("{any}\n", .{line.value.labels.items});
            }
            try self.writer.print("\n", .{});
        }
        std.debug.print("--------------------\n", .{});

        try self.renderFileStart(
            try sourceFiles.name(diagnostic.labels.items[0].fileId),
            try sourceFiles.location(diagnostic.labels.items[0].fileId, diagnostic.labels.items[0].start),
            padding + 1,
        );

        // NOTE: This should eventually be a loop over some kind of struct that contains the labels grouped by file
        for (diagnostic.labels.items) |label| {
            try self.renderLineNumber((try sourceFiles.location(label.fileId, label.start)).line, padding);
            try self.setColor(self.config.colors.border);
            try self.writer.print("{s}\n", .{self.config.charset.border});
            try self.resetColor();
        }

        if (diagnostic.notes.items.len > 0) try self.renderEmptyBorderLine(padding + 1);

        for (diagnostic.notes.items) |note| {
            try self.renderPadding(padding + 1); // +1 to account for the space after the line number
            try self.setColor(self.config.colors.noteMarker);
            try self.writer.print("{s} ", .{self.config.charset.noteMarker});
            try self.resetColor();
            try self.writer.print("{s}\n", .{note});
        }
    }

    fn renderMainMessage(
        self: *const Renderer,
        renderFileLoc: bool,
        severity: Severity,
        message: []const u8,
        fileName: []const u8,
        startLoc: LineCol,
    ) !void {
        if (renderFileLoc) {
            try self.renderFileLocation(fileName, startLoc);
            try self.writer.print(": ", .{});
        }

        try self.setColor(.bold);
        try self.setColor(self.config.colors.header(severity));
        switch (severity) {
            .Error => try self.writer.print("error", .{}),
            .Warning => try self.writer.print("warning", .{}),
            .Info => try self.writer.print("info", .{}),
        }
        try self.resetColor();

        try self.writer.print(": {s}\n", .{message});
    }

    fn renderFileStart(self: *const Renderer, fileName: []const u8, startLoc: LineCol, padding: usize) !void {
        try self.renderPadding(padding);

        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}", .{self.config.charset.headerStart});
        try self.writer.print("[ ", .{});
        try self.resetColor();

        try self.renderFileLocation(fileName, startLoc);
        try self.setColor(self.config.colors.border);
        try self.writer.print(" ]", .{});
        try self.resetColor();
        try self.writer.print("\n", .{});
        try self.renderEmptyBorderLine(padding);
    }

    /// Renders an empty border line with the specified `padding`.
    /// Appends a new line after rendering.
    fn renderEmptyBorderLine(self: *const Renderer, padding: usize) !void {
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}", .{self.config.charset.border});
        try self.resetColor();
        try self.writer.print("\n", .{});
    }

    /// Renders the line number padded to the right.
    /// The appropriate padding is calculated based on `padding` and the number of digits in `line`.
    /// Appends a space after the line number.
    fn renderLineNumber(self: *const Renderer, line: usize, padding: usize) !void {
        const iPadding: isize = @intCast(padding);
        const lineDigitLen: isize = @intCast(getDigitsLength(line));
        const t: isize = iPadding - lineDigitLen;

        try self.renderPadding(@max(0, t));
        try self.setColor(self.config.colors.lineNumber);
        try self.writer.print("{d}", .{line});
        try self.resetColor();
        try self.writer.print(" ", .{});
    }

    fn renderPadding(self: *const Renderer, padding: usize) !void {
        for (0..padding) |_| try self.writer.print(" ", .{});
    }

    /// Renders the file location in the format `fileName:line:col`.
    fn renderFileLocation(self: *const Renderer, fileName: []const u8, startLoc: LineCol) !void {
        try self.writer.print("{s}:{s}", .{ fileName, startLoc });
    }
};
