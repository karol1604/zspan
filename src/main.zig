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
        \\let add = 2;
        \\let x = 3;
        \\let y = 4;
        \\let z = 5;
        \\let z = add(x, y);
        \\let w = add(z, z);
        \\ let z = add(x, y) + add(z, w);
        \\let z = add(x, y) + add(z, w) + add(x, y);
        \\add(x, y) => x + y;
    ;
    const s = zspan.SourceFile.init("example.mp", source, alloc);
    const sources = &[_]zspan.SourceFile{s};

    for (s.lineStarts, 0..) |lineStart, i| {
        const lineEnd = if (i + 1 < s.lineStarts.len) s.lineStarts[i + 1] - 1 else s.source.len;
        const line = s.source[lineStart..lineEnd];
        std.debug.print("Line {d}: {s} [starts at: {d}]\n", .{ i + 1, line, lineStart });
    }

    const d = Diagnostic{
        .severity = .Error,
        .message = "This is an error",
        .labels = &[_]Label{
            Label.primary(5, 8, "Primary label", 0), // FIXME: temporary assumption
            Label.secondary(24, 27, "secondary label", 0), // FIXME: temporary assumption
            Label.secondary(34, 35, "Another secondary label", 0), // FIXME: temporary assumption
            Label.primary(72, 82, "Another primary label", 0), // FIXME: temporary assumption
            Label.secondary(153, 156, "Secondary label", 0), // FIXME: temporary assumption
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
    try zspan.displayDiagnostic(d, sources, stdout, alloc);

    try stdout.flush();
}
