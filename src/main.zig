//! By convention, main.zig is where your main function lives in the case that
const std = @import("std");
const lib = @import("codespan_lib");
const Label = lib.Label;

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    //
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // Don't forget to flush!
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    // Open the file for reading
    const file = try cwd.openFile(path, .{ .mode = .read_only });
    defer file.close();

    // Read whole file into a buffer (initial capacity 4 KiB)
    return try file.readToEndAlloc(allocator, 4096);
}

test "Diagnostic" {
    const alloc = std.testing.allocator;
    const source = try readFile(alloc, "text.md");
    defer alloc.free(source);

    var d = (try lib.Diagnostic.new(.Error, alloc)).withMessage("Type mismatch");
    // d = try d.withLabel(Label{
    //     .style = .Primary,
    //     .file = source,
    //     .start = 20,
    //     .end = 24,
    //     .message = "Expected type `Int`, found `Bool`",
    // });

    d = try d.withLabel(Label.primary(source, 17, 21).withMessage("Expected type `Int`, found `Bool`"));
    d = try d.withLabel(Label.secondary(source, 42, 44).withMessage("This is the value of the variable"));

    defer alloc.destroy(d);
    defer d.labels.deinit();

    std.debug.print("{s}", .{d});
}
