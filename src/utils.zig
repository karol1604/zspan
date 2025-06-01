const std = @import("std");

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
