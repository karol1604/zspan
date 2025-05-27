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

        try writer.print("{s}{s}{s}{s}", .{
            Color.bold,
            color,
            switch (self) {
                .Error => "error",
                .Warning => "warning",
                .Info => "info",
            },
            Color.reset,
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
            try writer.print("{s}", .{label});
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

    pub fn primary(file: []const u8, start: usize, end: usize) Label {
        return .{
            .style = .Primary,
            .file = file,
            .start = start,
            .end = end,
            .message = "",
        };
    }

    pub fn secondary(file: []const u8, start: usize, end: usize) Label {
        return .{
            .style = .Secondary,
            .file = file,
            .start = start,
            .end = end,
            .message = "",
        };
    }

    pub fn withMessage(self: Label, message: []const u8) Label {
        var copy = self;
        copy.message = message;
        return copy;
    }

    pub fn format(self: Label, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const line_col_start = self.line_col(self.start);
        const line_col_end = self.line_col(self.end);
        const line_start = findLineStart(self.file, self.start);
        const line_end = findLineEnd(self.file, self.start);

        const col = switch (self.style) {
            .Primary => Color.red,
            .Secondary => Color.reset,
        };

        var linePrefixBuf: [32]u8 = undefined;
        const linePrefix = std.fmt.bufPrint(&linePrefixBuf, "{d} │ ", .{line_col_start.line}) catch |err| {
            std.debug.panic("Failed to format line prefix: {s}", .{@errorName(err)});
        };

        try writer.print("{s}{s}{s}", .{
            Color.blue,
            linePrefix,
            Color.reset,
        });

        const lineOffset = line_start;
        try writer.print("{s}{s}{s}{s}{s}\n", .{
            self.file[line_start .. line_col_start.col + lineOffset],
            col,
            self.file[line_col_start.col + lineOffset .. line_col_end.col + lineOffset],
            Color.reset,
            self.file[line_col_end.col + lineOffset .. line_end],
        });

        // NOTE: we do `-2` bc the `│` is 3 bytes wide. this is kind of a hack but it works for now.
        for (0..linePrefix.len - 2) |_| try writer.print(" ", .{});
        for (0..line_col_start.col) |_| try writer.print(" ", .{});

        const c = switch (self.style) {
            .Primary => "^",
            .Secondary => "~",
        };
        const c_col = switch (self.style) {
            .Primary => Color.red,
            .Secondary => Color.blue,
        };
        try writer.print("{s}", .{c_col});

        for (0..self.end - self.start) |_| {
            try writer.print("{s}", .{c});
        }

        try writer.print(" {s}", .{self.message});

        try writer.print("{s}\n", .{Color.reset});
    }
};
