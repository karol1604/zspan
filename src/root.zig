const std = @import("std");
// const Colors = @import("colors.zig");

const Color = struct {
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const bold = "\x1b[1m";
    pub const reset = "\x1b[0m";
};

pub const Severity = enum {
    Error,
    Warning,
    Info,

    pub fn format(self: Severity, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const color = switch (self) {
            .Error => Color.red,
            .Warning => Color.yellow,
            .Info => Color.blue,
        };

        try writer.print("{s}{s}{s}{s}{s}", .{
            "\x1b[1m",

            color,
            switch (self) {
                .Error => "error",
                .Warning => "warning",
                .Info => "info",
            },
            Color.reset,
            "\x1b[0m",
        });
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    labels: std.ArrayList(Label),
    alloc: std.mem.Allocator,

    pub fn new(severity: Severity, alloc: std.mem.Allocator) !*Diagnostic {
        const ptr = try alloc.create(Diagnostic);
        ptr.* = .{
            .severity = severity,
            .message = "",
            .labels = std.ArrayList(Label).init(alloc),
            .alloc = alloc,
        };

        return ptr;
    }

    pub fn withMessage(self: *Diagnostic, message: []const u8) *Diagnostic {
        self.message = message;
        return self;
    }

    pub fn withLabel(self: *Diagnostic, label: Label) !*Diagnostic {
        try self.labels.append(label);
        return self;
    }

    pub fn format(self: Diagnostic, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}: {s}\n", .{
            self.severity,
            self.message,
        });
        try writer.print("{s}:{s}\n", .{ "stdin", self.labels.items[0].line_col(self.labels.items[0].start) });

        for (self.labels.items) |label| {
            const line_col_start = label.line_col(label.start);
            const line_col_end = label.line_col(label.end);
            const line_start = findLineStart(label.file, label.start);
            const line_end = findLineEnd(label.file, label.start);

            // std.debug.print("line_col_start: {s}, line_col_end: {s}, line_start: {d}, line_end: {d}\n", .{
            //     line_col_start,
            //     line_col_end,
            //     line_start,
            //     line_end,
            // });
            //
            try writer.print("{s}{s}{s}{s}{s}\n", .{
                label.file[line_start .. line_col_start.col + line_start],
                Color.red,
                label.file[line_col_start.col + line_start .. line_col_end.col + line_start],
                Color.reset,
                label.file[line_col_end.col + line_start .. line_end],
            });

            for (0..line_col_start.col) |_| {
                try writer.print(" ", .{});
            }

            try writer.print("{s}", .{Color.red});

            for (0..label.end - label.start) |_| {
                try writer.print("^", .{});
            }

            try writer.print(" {s}", .{label.message});

            try writer.print("{s}\n", .{Color.reset});
        }
    }
};

fn findLineStart(source: []const u8, start: usize) usize {
    var i = start;
    while (i > 0) : (i -= 1) {
        if (source[i] == '\n') {
            return i + 1; // Return the character after the newline
        }
    }
    return 0; // If no newline found, return the start of the source
}

fn findLineEnd(source: []const u8, start: usize) usize {
    var i = start;
    while (i < source.len) : (i += 1) {
        if (source[i] == '\n') {
            return i;
        }
    }
    return source.len;
}

const LineCol = struct {
    line: usize,
    col: usize,

    pub fn format(self: LineCol, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}:{d}", .{ self.line, self.col });
    }
};

pub const Label = struct {
    style: enum {
        Primary,
        Secondary,
    },
    start: usize,
    end: usize,
    message: []const u8,
    file: []const u8,

    pub fn line_col(self: *const Label, idx: usize) LineCol {
        var line: usize = 1;
        var col: usize = 1;
        var pos: usize = 1;

        for (self.file) |b| {
            if (pos >= idx) break;
            switch (b) {
                '\n' => {
                    line += 1;
                    col = 1;
                },
                else => {
                    col += 1;
                },
            }
            pos += 1;
        }

        return LineCol{ .line = line, .col = col };
    }
};
