const std = @import("std");
const fileModule = @import("simple-file.zig");
pub const SimpleFile = fileModule.SimpleFile;
pub const SimpleFiles = fileModule.SimpleFiles;
const utils = @import("utils.zig");
const Color = utils.Color;
const Config = @import("config.zig").Config;
// const Colors = @import("colors.zig");

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

fn getDigitsLength(n: usize) usize {
    return std.math.log10_int(n) + 1;
}

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    labels: std.ArrayList(Label),
    notes: std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    config: Config, // TODO: move this to the renderer when we have one

    pub fn new(severity: Severity, alloc: std.mem.Allocator) *Diagnostic {
        const ptr = alloc.create(Diagnostic) catch {
            @panic("Failed to allocate Diagnostic");
        };

        ptr.* = .{
            .severity = severity,
            .message = "",
            .labels = std.ArrayList(Label).init(alloc),
            .notes = std.ArrayList([]const u8).init(alloc),
            .alloc = alloc,
            .config = Config.default(), // Default to UTF-8 config
        };

        return ptr;
    }

    pub fn withMessage(self: *Diagnostic, message: []const u8) *Diagnostic {
        self.message = message;
        return self;
    }

    pub fn withLabels(self: *Diagnostic, labels: []const Label) *Diagnostic {
        for (labels) |label| {
            self.labels.append(label) catch |err| {
                std.debug.panic("Failed to append label: {s}", .{@errorName(err)});
            };
        }
        return self;
    }

    pub fn withNote(self: *Diagnostic, note: []const u8) *Diagnostic {
        self.notes.append(note) catch |err| {
            std.debug.panic("Failed to append note: {s}", .{@errorName(err)});
        };
        return self;
    }

    pub fn withNotes(self: *Diagnostic, notes: []const []const u8) *Diagnostic {
        for (notes) |note| {
            self.notes.append(note) catch |err| {
                std.debug.panic("Failed to append note: {s}", .{@errorName(err)});
            };
        }
        return self;
    }

    fn getMaxLineNumberLength(self: *const Diagnostic) usize {
        var max_length: usize = 0;
        for (self.labels.items) |label| {
            const line = label.line_col(label.start).line;
            const lineLength = getDigitsLength(line);

            if (lineLength > max_length) {
                max_length = lineLength;
            }
        }
        return max_length;
    }

    pub fn format(self: Diagnostic, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}: {s}\n", .{
            self.severity,
            self.message,
        });

        const maxLineNumLength = self.getMaxLineNumberLength();

        for (0..maxLineNumLength) |_| try writer.print(" ", .{});

        // try writer.print("{s} ┌─ {s}", .{ Color.blue, Color.reset });
        try writer.print("{s} {s} {s}", .{ Color.blue, self.config.charset.headerStart, Color.reset });
        try writer.print("{s}:{s}\n", .{ self.labels.items[0].file.name, self.labels.items[0].line_col(self.labels.items[0].start) });

        for (0..maxLineNumLength) |_| try writer.print(" ", .{});

        // try writer.print("{s} │\n{s}", .{ Color.blue, Color.reset });
        try writer.print("{s} {s}\n{s}", .{ Color.blue, self.config.charset.border, Color.reset });

        var lastLineNum: usize = undefined;
        for (self.labels.items) |label| {
            const line = label.line_col(label.start).line;

            if (line != lastLineNum) {
                for (0..maxLineNumLength - getDigitsLength(line)) |_| try writer.print(" ", .{});

                // try writer.print("{s}{d} │ {s}", .{
                //     Color.blue,
                //     line,
                //     Color.reset,
                // });
                try writer.print("{s}{d} {s} {s}", .{
                    Color.blue,
                    line,
                    self.config.charset.border,
                    Color.reset,
                });
            }

            var buffer: [256]u8 = undefined;

            const offset = maxLineNumLength + 1; // lineDigits + " "
            try writer.print("{s}", .{try label.toString(&buffer, offset, line == lastLineNum, self.config)});
            lastLineNum = line;
        }

        for (0..maxLineNumLength) |_| try writer.print(" ", .{});

        // try writer.print("{s} │ \n", .{Color.blue});
        try writer.print("{s} {s} \n", .{ Color.blue, self.config.charset.border });
        for (self.notes.items) |note| {
            for (0..self.getMaxLineNumberLength() + 1) |_| try writer.print(" ", .{});
            // try writer.print("{s}= {s}{s}\n", .{ Color.blue, Color.reset, note });
            try writer.print("{s}{s} {s}{s}\n", .{ Color.blue, self.config.charset.noteMarker, Color.reset, note });
        }

        try writer.print("{s}", .{Color.reset});
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
    file: *const SimpleFile,

    pub fn line_col(self: *const Label, idx: usize) LineCol {
        var line: usize = 1;
        var col: usize = 1;
        var pos: usize = 1;

        for (self.file.*.source) |b| {
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

    pub fn primary(file: *const SimpleFile, start: usize, end: usize) Label {
        return .{
            .style = .Primary,
            .file = file,
            .start = start,
            .end = end,
            .message = "",
        };
    }

    pub fn secondary(file: *const SimpleFile, start: usize, end: usize) Label {
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
        // const line_start = findLineStart(self.file.*.source, self.start);
        const line_start = self.file.*.lineStart(self.start) catch |err| {
            std.debug.panic("Failed to get line start: {s}", .{@errorName(err)});
        };
        const line_end = findLineEnd(self.file.*.source, self.start);

        const col = switch (self.style) {
            .Primary => Color.red,
            .Secondary => Color.reset,
        };

        const lineOffset = line_start;
        try writer.print("{s}{s}{s}{s}{s}\n", .{
            self.file.*.source[line_start .. line_col_start.col + lineOffset],
            col,
            self.file.*.source[line_col_start.col + lineOffset .. line_col_end.col + lineOffset],
            Color.reset,
            self.file.*.source[line_col_end.col + lineOffset .. line_end],
        });

        // for (0..line_col_start.col) |_| try writer.print(" ", .{});
        //
        // const c = switch (self.style) {
        //     .Primary => "^",
        //     .Secondary => "~",
        // };
        // const c_col = switch (self.style) {
        //     .Primary => Color.red,
        //     .Secondary => Color.blue,
        // };
        // try writer.print("{s}", .{c_col});
        //
        // for (0..self.end - self.start) |_| try writer.print("{s}", .{c});
        //
        // try writer.print(" {s}", .{self.message});
        //
        // try writer.print("{s}\n", .{Color.reset});
    }

    pub fn toString(self: Label, buf: []u8, labelOffset: usize, sameLastLine: bool, config: Config) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const writer = stream.writer();

        const line_col_start = self.line_col(self.start);

        if (!sameLastLine) try writer.print("{s}", .{self}); // this prints the code line

        for (0..labelOffset) |_| try writer.print(" ", .{});
        // try writer.print("{s}│{s}", .{ Color.blue, Color.reset });
        try writer.print("{s}{s}{s}", .{ Color.blue, config.charset.border, Color.reset });

        // NOTE: we do `+1` to account for the `│` char
        for (0..line_col_start.col + 1) |_| try writer.print(" ", .{});

        const c = switch (self.style) {
            .Primary => "^",
            .Secondary => "~",
        };
        const c_col = switch (self.style) {
            .Primary => Color.red,
            .Secondary => Color.blue,
        };
        try writer.print("{s}", .{c_col});

        for (0..self.end - self.start) |_| try writer.print("{s}", .{c});

        try writer.print(" {s}", .{self.message});

        try writer.print("{s}\n", .{Color.reset});

        return buf[0..stream.pos];
    }
};
