const std = @import("std");
const zspan = @import("zspan");
const Diagnostic = zspan.Diagnostic;
const Label = zspan.Label;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const source =
        \\add: Int × Int -> Int;
        \\let Int = 1;
        \\add(x, y) => x + y;
    ;
    const s = zspan.SourceFile.init("example.mp", source, alloc);

    for (s.lineStarts, 0..) |lineStart, i| {
        const lineEnd = if (i + 1 < s.lineStarts.len) s.lineStarts[i + 1] - 1 else s.source.len;
        const line = s.source[lineStart..lineEnd];
        std.debug.print("Line {d}: {s} [starts at: {d}]\n", .{ i + 1, line, lineStart });
    }

    const d = Diagnostic{
        .severity = .Error,
        .message = "This is an error",
        .labels = &[_]Label{
            Label.primary(10, 15, "Primary label", &s),
            Label.secondary(20, 25, "Secondary label", &s),
        },
        .notes = &[_][]const u8{
            "This is a note",
            "This is another note",
        },
    };

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("hello\n", .{});
    try zspan.displayDiagnostic(d, s, stdout);

    try stdout.flush();
}
