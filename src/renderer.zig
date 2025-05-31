const std = @import("std");
const Config = @import("config.zig").Config;
const Severity = @import("diagnostic.zig").Severity;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const SourceFiles = @import("source-file.zig").SourceFiles;
const SourceFile = @import("source-file.zig").SourceFile;
const LineCol = @import("diagnostic.zig").LineCol;

pub const Renderer = struct {
    config: Config,
    writer: std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter, config: Config) Renderer {
        return .{
            .writer = writer,
            .config = config,
        };
    }

    // renderer code here...

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
    }

    fn renderMainMessage(self: *const Renderer, renderFileLoc: bool, severity: Severity, message: []const u8, fileName: []const u8, startLoc: LineCol) !void {
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

    fn renderFileLocation(self: *const Renderer, fileName: []const u8, startLoc: LineCol) !void {
        try self.writer.print("{s}:{s}", .{ fileName, startLoc });
    }
};
