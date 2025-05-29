//! By convention, main.zig is where your main function lives in the case that
const std = @import("std");

const lib = @import("codespan_lib");
const Label = lib.Label;
const SimpleFiles = lib.SimpleFiles;
const Renderer = lib.Renderer;
const Config = lib.Config;

// const file_ = @import("simple-file.zig");
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    // const source = try readFile(alloc, "text.md");
    defer arena.deinit();

    var test_files = (try SimpleFiles.init(alloc));
    try test_files.addFile("text.md", try readFile(alloc, "text.md"));

    const d = lib.Diagnostic.new(.Error, alloc)
        .withMessage("Type mismatch")
        .withLabels(
            &[_]Label{
                Label.primary(&test_files.files.items[0], 14, 18).withMessage("Expected type `Int`, found `Bool`"),
                Label.secondary(&test_files.files.items[0], 14, 18).withMessage("Expected type `Int`, found `Bool`"),
                Label.secondary(&test_files.files.items[0], 35 + 100, 37 + 100).withMessage("This is the value of the variable"),
            },
        )
        .withNotes(
        &[_][]const u8{
            "This is a note about the error.",
            "This is another note about the error.",
        },
    );

    // defer alloc.destroy(d);
    // defer d.labels.deinit();
    // defer d.notes.deinit();

    var writer = std.io.getStdErr().writer().any();
    // try std.io.tty.Config.setColor(.escape_codes, writer, .dim);
    try writer.print("Diagnostic:\n", .{});

    std.debug.print("{s}", .{d});

    const r = Renderer.init(writer, Config.default());
    try r.renderMainMessage(d.severity, d.message);

    // NOTE: api should be like this:
    // renderer.renderDiagnostic(writer, &files, &diagnostic);
}
