const std = @import("std");
const Config = @import("config.zig").Config;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const SourceFile = @import("sourcefile.zig").SourceFile;
const LineCol = @import("utils.zig").LineCol;

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

    pub fn renderDiagnostic(self: *Renderer, diagnostic: Diagnostic, sourceFile: SourceFile) !void {
        try self.renderMainMessage(diagnostic);
        try self.renderFileHeader(sourceFile.name, LineCol{ .line = 1, .col = 1 });
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

    fn renderFileHeader(self: *Renderer, fileName: []const u8, lineCol: LineCol) !void {
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

    fn renderFileLocation(self: *const Renderer, fileName: []const u8, startLoc: LineCol) !void {
        try self.writer.print("{s}:{f}", .{ fileName, startLoc });
    }
};
