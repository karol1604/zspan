const std = @import("std");
const utils = @import("utils.zig");

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

pub const SimpleFile = struct {
    name: []const u8,
    source: []const u8,
    lineStarts: []const usize,

    pub fn init(name: []const u8, source: []const u8, alloc: std.mem.Allocator) SimpleFile {
        return .{
            .name = name,
            .source = source,
            .lineStarts = getLineStarts(source, alloc), // TODO: Calculate line starts
        };
    }

    fn lineIndex(self: *const SimpleFile, byteOffset: usize) usize {
        return utils.binarySearch(usize, self.lineStarts, byteOffset);
    }

    pub fn lineStart(self: *const SimpleFile, byteOffset: usize) !usize {
        const lineIdx = self.lineIndex(byteOffset);
        if (lineIdx < self.lineStarts.len) return self.lineStarts[lineIdx];
        if (lineIdx == self.lineStarts.len) return self.source.len;

        return error.OutOfRange;
    }
};

pub const SimpleFiles = struct {
    files: std.ArrayList(SimpleFile),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !SimpleFiles {
        return .{
            .alloc = alloc,
            .files = std.ArrayList(SimpleFile).init(alloc),
        };
    }

    pub fn deinit(self: *SimpleFiles) void {
        self.files.deinit();
    }

    pub fn addFile(self: *SimpleFiles, name: []const u8, source: []const u8) !void {
        try self.files.append(SimpleFile.init(name, source, self.alloc));
    }
};
