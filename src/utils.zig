const std = @import("std");

pub fn OrderedMap(comptime K: type, comptime V: type) type {
    return struct {
        const KeyValue = struct {
            key: K,
            value: V,
        };

        const Self = @This();
        alloc: std.mem.Allocator,
        items: std.ArrayList(KeyValue),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .alloc = alloc,
                .items = std.ArrayList(KeyValue).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        fn find_index(self: *const Self, key: K) ?usize {
            var left: usize = 0;
            var right: usize = self.items.items.len;
            while (left < right) {
                const mid = (left + right) / 2;
                if (self.items.items[mid].key == key) return mid;
                if (self.items.items[mid].key < key) {
                    left = mid + 1;
                } else {
                    right = mid;
                }
            }
            return null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            const idx = self.find_index(key);
            return if (idx) |i| self.items.items[i].value else null;
        }

        pub fn insert(self: *Self, key: K, value: V) !V {
            var idx: usize = 0;
            while (idx < self.items.items.len and self.items.items[idx].key < key) {
                idx += 1;
            }
            if (idx < self.items.items.len and self.items.items[idx].key == key) {
                self.items.items[idx].value = value; // replace existing
                return value; // return updated value
            } else {
                try self.items.insert(idx, .{ .key = key, .value = value });
                return value; // insert new
            }
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.items.len == 0;
        }
    };
}

pub const Range = struct {
    start: usize,
    end: usize,

    pub fn contains(self: *const Range, value: usize) bool {
        return value >= self.start and value < self.end;
    }

    pub fn length(self: *const Range) usize {
        return self.end - self.start;
    }

    pub fn isEmpty(self: *const Range) bool {
        return self.start == self.end;
    }
};

pub const Color = struct {
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const bold = "\x1b[1m";
    pub const reset = "\x1b[0m";
};

pub fn getDigitsLength(n: usize) usize {
    return std.math.log10_int(n) + 1;
}

pub const LineCol = struct {
    line: usize,
    col: usize,

    pub fn format(self: LineCol, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}:{d}", .{ self.line, self.col });
    }
};

pub fn binarySearch(
    comptime T: type,
    arr: []const T,
    target: T,
) usize {
    var low: usize = 0;
    var high: usize = arr.len;

    while (low < high) {
        const mid = (low + high) / 2;
        const v = arr[mid];
        if (v < target) {
            low = mid + 1;
        } else if (v > target) {
            high = mid;
        } else {
            return mid;
        }
    }
    return low - 1;
}
