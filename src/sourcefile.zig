const std = @import("std");
const utils = @import("utils.zig");
const Range = utils.Range;
const LineCol = utils.LineCol;

fn getLineStarts(source: []const u8, alloc: std.mem.Allocator) []usize {
    var view = std.unicode.Utf8View.init(source) catch |err| {
        std.debug.panic("Failed to create UTF-8 view: {}", .{err});
    };
    var iter = view.iterator();

    var lineStarts: std.ArrayList(usize) = .empty;
    lineStarts.append(alloc, 0) catch |err| {
        std.debug.panic("Failed to allocate line starts: {}", .{err});
    };

    var curByteOffset: usize = 0;
    while (iter.nextCodepoint()) |c| {
        const len = std.unicode.utf8CodepointSequenceLength(c) catch |err| {
            std.debug.panic("Failed to get UTF-8 codepoint length: {}", .{err});
        };
        const byteLen: usize = @intCast(len);
        curByteOffset += byteLen;

        if (c == '\n') {
            lineStarts.append(alloc, curByteOffset) catch |err| {
                std.debug.panic("Failed to allocate line starts: {}", .{err});
            };
        }
    }

    return lineStarts.toOwnedSlice(alloc) catch |err| {
        std.debug.panic("Failed to allocate line starts: {}", .{err});
    };
}

pub fn displayCol(source: []const u8, from: usize, to: usize) usize {
    var col: usize = 0;
    var view = std.unicode.Utf8View.init(source[from..to]) catch return to - from;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |_| col += 1;
    return col;
}

pub fn displayWidth(source: []const u8, from: usize, to: usize) usize {
    return displayCol(source, from, to);
}

pub const SourceFile = struct {
    name: []const u8,
    source: []const u8,
    lineStarts: []const usize,

    pub fn init(name: []const u8, source: []const u8, alloc: std.mem.Allocator) SourceFile {
        return SourceFile{
            .name = name,
            .source = source,
            .lineStarts = getLineStarts(source, alloc),
        };
    }

    /// Returns the index of the line containing the given byte offset
    fn lineIndex(self: SourceFile, byteOffset: usize) usize {
        return utils.binarySearch(usize, self.lineStarts, byteOffset);
    }

    pub fn lineStart(self: *const SourceFile, byteOffset: usize) !usize {
        const lineIdx = self.lineIndex(byteOffset);
        if (lineIdx < self.lineStarts.len) return self.lineStarts[lineIdx];
        if (lineIdx == self.lineStarts.len) return self.source.len;

        return error.LineIndexOutOfRange;
    }

    // TODO: this is ugly
    pub fn lineRange(self: *const SourceFile, byteOffset: usize) !Range {
        const start = try self.lineStart(byteOffset);
        const lineIdx = self.lineIndex(byteOffset);
        const nextLineStart = if (lineIdx + 1 < self.lineStarts.len) self.lineStarts[lineIdx + 1] else self.source.len;
        const end = nextLineStart - 1;
        return Range{ .start = start, .end = end };
    }

    pub fn lineCol(self: *const SourceFile, byteOffset: usize) !LineCol {
        const lineIdx = self.lineIndex(byteOffset);
        if (lineIdx >= self.lineStarts.len) {
            return error.ByteOffsetOutOfRange;
        }

        const ls = self.lineStarts[lineIdx];
        const col = displayCol(self.source, ls, byteOffset);
        return LineCol{ .line = lineIdx + 1, .col = col + 1 };
    }

    pub fn lineIndexAt(self: *const SourceFile, offset: usize) !usize {
        const lineIdx = self.lineIndex(offset);
        if (lineIdx >= self.lineStarts.len) {
            return error.ByteOffsetOutOfRange;
        }
        return lineIdx;
    }

    pub fn lineRangeAtIndex(self: *const SourceFile, lineIdx: usize) !Range {
        if (lineIdx >= self.lineStarts.len) {
            return error.LineIndexOutOfRange;
        }
        const start = self.lineStarts[lineIdx];
        const nextLineStart = if (lineIdx + 1 < self.lineStarts.len) self.lineStarts[lineIdx + 1] else self.source.len;
        const end = nextLineStart - 1;
        return Range{ .start = start, .end = end };
    }
};
