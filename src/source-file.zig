const std = @import("std");
const utils = @import("utils.zig");
const LineCol = @import("utils.zig").LineCol;
const Range = @import("utils.zig").Range;

fn getLineStarts(source: []const u8, alloc: std.mem.Allocator) []const usize {
    var lineStarts: std.ArrayList(usize) = std.ArrayList(usize).init(alloc);
    var pos: usize = 0;

    // Add the start of the file
    _ = lineStarts.append(0) catch |err| {
        std.debug.panic("Failed to append start of file: {s}", .{@errorName(err)});
    };

    for (source) |c| {
        if (c == '\n') {
            _ = lineStarts.append(pos + 1) catch |err| {
                std.debug.panic("Failed to append line start: {s}", .{@errorName(err)});
            };
        }
        pos += 1;
    }

    // Add the end of the file
    return lineStarts.items;
}

pub const SourceFile = struct {
    name: []const u8,
    source: []const u8,
    lineStarts: []const usize,

    pub fn init(name: []const u8, source: []const u8, alloc: std.mem.Allocator) SourceFile {
        return .{
            .name = name,
            .source = source,
            .lineStarts = getLineStarts(source, alloc), // TODO: Calculate line starts
        };
    }

    /// Returns the index of the line that contains the given byte offset.
    fn lineIndex(self: *const SourceFile, byteOffset: usize) usize {
        return utils.binarySearch(usize, self.lineStarts, byteOffset);
    }

    pub fn lineStart(self: *const SourceFile, byteOffset: usize) !usize {
        const lineIdx = self.lineIndex(byteOffset);
        if (lineIdx < self.lineStarts.len) return self.lineStarts[lineIdx];
        if (lineIdx == self.lineStarts.len) return self.source.len;

        return error.LineIndexOutOfRange;
    }

    // TODO: this is ugly
    fn lineRange(self: *const SourceFile, byteOffset: usize) !Range {
        const start = try self.lineStart(byteOffset);
        const lineIdx = self.lineIndex(byteOffset);
        const nextLineStart = if (lineIdx + 1 < self.lineStarts.len) self.lineStarts[lineIdx + 1] else self.source.len;
        const end = nextLineStart - 1;
        return Range{ .start = start, .end = end };
    }
};

pub const SourceFiles = struct {
    files: std.ArrayList(SourceFile),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !SourceFiles {
        return .{
            .alloc = alloc,
            .files = std.ArrayList(SourceFile).init(alloc),
        };
    }

    pub fn location(self: *const SourceFiles, fileId: usize, byteOffset: usize) !LineCol {
        if (fileId >= self.files.items.len) return error.FileIdOutOfRange;

        const file = &self.files.items[fileId];
        const lineStart = try file.lineStart(byteOffset);
        const lineIdx = file.lineIndex(byteOffset);
        const column = byteOffset - lineStart;

        return .{
            .line = lineIdx + 1, // Lines are 1-indexed
            .col = column + 1, // Columns are 1-indexed
        };
    }

    pub fn lineIndex(self: *const SourceFiles, fileId: usize, byteOffset: usize) !usize {
        if (fileId < self.files.items.len) {
            return self.files.items[fileId].lineIndex(byteOffset);
        }
        return error.FileIdOutOfRange;
    }

    pub fn lineRange(self: *const SourceFiles, fileId: usize, byteOffset: usize) !Range {
        if (fileId < self.files.items.len) {
            return self.files.items[fileId].lineRange(byteOffset);
        }
        return error.FileIdOutOfRange;
    }

    pub fn name(self: *const SourceFiles, fileId: usize) ![]const u8 {
        if (fileId < self.files.items.len) {
            return self.files.items[fileId].name;
        }
        return error.FileIdOutOfRange;
    }

    pub fn source(self: *const SourceFiles, fileId: usize) ![]const u8 {
        if (fileId < self.files.items.len) {
            return self.files.items[fileId].source;
        }
        return error.FileIdOutOfRange;
    }

    pub fn addFile(self: *SourceFiles, name_: []const u8, source_: []const u8) !usize {
        try self.files.append(SourceFile.init(name_, source_, self.alloc));
        return self.files.items.len - 1;
    }

    pub fn deinit(self: *SourceFiles) void {
        self.files.deinit();
    }
};
