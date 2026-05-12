const std = @import("std");
const snapshot_options = @import("snapshot_options");

const snapshot_dir = "tests/snapshots";
const max_snapshot_size = 1024 * 1024;

pub fn expectSnapshot(
    alloc: std.mem.Allocator,
    name: []const u8,
    actual: []const u8,
) !void {
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const path = try std.fmt.allocPrint(alloc, "{s}/{s}.snap", .{ snapshot_dir, name });
    defer alloc.free(path);

    const expected = cwd.readFileAlloc(
        io,
        path,
        alloc,
        .limited(max_snapshot_size),
    ) catch |err| switch (err) {
        error.FileNotFound => {
            if (snapshot_options.update_snapshots) {
                try cwd.writeFile(io, .{ .sub_path = path, .data = actual });
                return;
            }

            std.debug.print(
                "missing snapshot '{s}'. Re-run with -Dupdate-snapshots=true to create it.\n",
                .{path},
            );
            return error.SnapshotMissing;
        },
        else => return err,
    };
    defer alloc.free(expected);

    if (std.mem.eql(u8, expected, actual)) return;

    if (snapshot_options.update_snapshots) {
        try cwd.writeFile(io, .{ .sub_path = path, .data = actual });
        return;
    }

    printFirstDifference(path, expected, actual);
    return error.SnapshotMismatch;
}

fn printFirstDifference(path: []const u8, expected: []const u8, actual: []const u8) void {
    var expected_lines = std.mem.splitScalar(u8, expected, '\n');
    var actual_lines = std.mem.splitScalar(u8, actual, '\n');
    var line_number: usize = 1;

    while (true) : (line_number += 1) {
        const expected_line = expected_lines.next();
        const actual_line = actual_lines.next();

        if (expected_line == null and actual_line == null) break;

        if (expected_line == null or actual_line == null or
            !std.mem.eql(u8, expected_line orelse "", actual_line orelse ""))
        {
            std.debug.print(
                "snapshot mismatch in '{s}' at line {d}\nexpected: {s}\nactual:   {s}\n",
                .{
                    path,
                    line_number,
                    expected_line orelse "<end of snapshot>",
                    actual_line orelse "<end of output>",
                },
            );
            return;
        }
    }
}
