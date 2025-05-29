const std = @import("std");
const Config = @import("config.zig").Config;
const Severity = @import("root.zig").Severity;

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

    pub fn renderMainMessage(self: *const Renderer, severity: Severity, message: []const u8) !void {
        try self.setColor(.bold);
        switch (severity) {
            .Error => {
                try self.setColor(.red);
                try self.writer.print("error", .{});
            },
            .Warning => {
                try self.setColor(.yellow);
                try self.writer.print("warning", .{});
            },
            .Info => {
                try self.setColor(.cyan);
                try self.writer.print("info", .{});
            },
        }

        try self.resetColor();

        try self.writer.print(": {s}", .{message});
    }
};
