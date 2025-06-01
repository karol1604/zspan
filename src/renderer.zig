const std = @import("std");
const Config = @import("config.zig").Config;
const Severity = @import("diagnostic.zig").Severity;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const SourceFiles = @import("source-file.zig").SourceFiles;
const SourceFile = @import("source-file.zig").SourceFile;
const LineCol = @import("utils.zig").LineCol;
const getDigitsLength = @import("utils.zig").getDigitsLength;

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

        var padding: usize = 0;

        for (diagnostic.labels.items) |label| {
            padding = @max(padding, getDigitsLength((try sourceFiles.location(label.fileId, label.start)).line));
        }

        try self.renderFileStart(
            try sourceFiles.name(diagnostic.labels.items[0].fileId),
            try sourceFiles.location(diagnostic.labels.items[0].fileId, diagnostic.labels.items[0].start),
            padding,
        );
    }

    // fn getMaxLineNumberLength(self: *const Diagnostic) usize {
    //     var max_length: usize = 0;
    //     for (self.labels.items) |label| {
    //         const line = label.line_col(label.start).line;
    //         const lineLength = getDigitsLength(line);
    //
    //         if (lineLength > max_length) {
    //             max_length = lineLength;
    //         }
    //     }
    //     return max_length;
    // }

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
        try self.writer.print(" ", .{});
        try self.resetColor();

        try self.renderFileLocation(fileName, startLoc);
        try self.writer.print("\n", .{});
        try self.renderEmptyBorderLine(padding);
    }

    fn renderEmptyBorderLine(self: *const Renderer, padding: usize) !void {
        try self.renderPadding(padding);
        try self.setColor(self.config.colors.border);
        try self.writer.print("{s}", .{self.config.charset.border});
        try self.resetColor();
        try self.writer.print("\n", .{});
    }

    fn renderPadding(self: *const Renderer, padding: usize) !void {
        for (0..padding + 1) |_| try self.writer.print(" ", .{});
    }

    fn renderFileLocation(self: *const Renderer, fileName: []const u8, startLoc: LineCol) !void {
        try self.writer.print("{s}:{s}", .{ fileName, startLoc });
    }
};
