const std = @import("std");

pub const LineCol = struct {
    line: usize,
    col: usize,

    pub fn format(self: LineCol, writer: *std.io.Writer) !void {
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
