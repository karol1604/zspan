const std = @import("std");
const zspan = @import("zspan");
const snapshot = @import("snapshot.zig");

const Diagnostic = zspan.Diagnostic;
const Label = zspan.Label;
const SourceFile = zspan.SourceFile;

const ByteSpan = struct {
    start: usize,
    end: usize,
};

fn renderDiagnostic(
    alloc: std.mem.Allocator,
    source_name: []const u8,
    source_text: []const u8,
    diagnostic: Diagnostic,
) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const render_alloc = arena.allocator();

    const source = SourceFile.init(source_name, source_text, render_alloc);
    const sources = &[_]SourceFile{source};

    var buffer = std.Io.Writer.Allocating.init(alloc);
    errdefer buffer.deinit();

    var config = zspan.Config.default();
    config.colorMode = .no_color;

    var renderer = zspan.Renderer.init(config, &buffer.writer);
    try renderer.renderDiagnostic(diagnostic, sources, render_alloc);

    return try buffer.toOwnedSlice();
}

fn spanOf(source: []const u8, needle: []const u8) ByteSpan {
    const start = std.mem.indexOf(u8, source, needle) orelse unreachable;
    return .{
        .start = start,
        .end = start + needle.len,
    };
}

fn offsetOf(source: []const u8, needle: []const u8) usize {
    return spanOf(source, needle).start;
}

test "single-line primary label snapshot" {
    const alloc = std.testing.allocator;
    const source = "let answer: bool = 42;";
    const labels = [_]Label{
        Label.primary(19, 21, "expected bool", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "mismatched type",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "single.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "single_line_primary", actual);
}

test "overlapping single-line labels snapshot" {
    const alloc = std.testing.allocator;
    const source = "let total = add(lhs, rhs);";
    const labels = [_]Label{
        Label.primary(12, 25, "call result", 0),
        Label.secondary(16, 19, "left input", 0),
        Label.secondary(21, 24, "right input", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "invalid call inputs",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "overlap.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "overlapping_single_line_labels", actual);
}

test "non-overlapping multiline labels snapshot" {
    const alloc = std.testing.allocator;
    const source =
        \\fn main() {
        \\    let value = compute(
        \\        left,
        \\        right,
        \\    );
        \\}
    ;
    const labels = [_]Label{
        Label.primary(28, 70, "multi-line expression", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "expression spans multiple lines",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "multiline.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "multiline_non_overlapping", actual);
}

test "notes snapshot" {
    const alloc = std.testing.allocator;
    const source = "const value = impossible;";
    const labels = [_]Label{
        Label.primary(14, 24, "unknown symbol", 0),
    };
    const notes = [_][]const u8{
        "names are resolved after parsing",
        "check the surrounding scope",
    };
    const diagnostic = Diagnostic{
        .severity = .warning,
        .message = "unresolved identifier",
        .labels = &labels,
        .notes = &notes,
    };

    const actual = try renderDiagnostic(alloc, "notes.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "notes", actual);
}

test "secondary single-line label snapshot" {
    const alloc = std.testing.allocator;
    const source = "let sum = lhs + rhs;";
    const rhs = spanOf(source, "rhs");
    const labels = [_]Label{
        Label.secondary(rhs.start, rhs.end, "secondary context", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .info,
        .message = "supporting location",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "secondary.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "secondary_single_line", actual);
}

test "zero-width label snapshot" {
    const alloc = std.testing.allocator;
    const source = "let value = ;";
    const insert_at = offsetOf(source, ";");
    const labels = [_]Label{
        Label.primary(insert_at, insert_at, "expected expression", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "missing expression",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "zero_width.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "zero_width_label", actual);
}

test "disconnected labeled regions snapshot" {
    const alloc = std.testing.allocator;
    const source =
        \\let first = bad();
        \\let untouched = 1;
        \\let still_untouched = 2;
        \\let last = worse();
    ;
    const bad = spanOf(source, "bad()");
    const worse = spanOf(source, "worse()");
    const labels = [_]Label{
        Label.primary(bad.start, bad.end, "first failure", 0),
        Label.secondary(worse.start, worse.end, "later context", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .warning,
        .message = "multiple interesting regions",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "regions.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "disconnected_regions", actual);
}

test "multiline label starting at column zero snapshot" {
    const alloc = std.testing.allocator;
    const source =
        \\alpha(
        \\    beta,
        \\    gamma,
        \\)
    ;
    const alpha = offsetOf(source, "alpha");
    const close = offsetOf(source, ")");
    const labels = [_]Label{
        Label.primary(alpha, close + 1, "full call", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "column-zero multiline start",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "column_zero.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "multiline_column_zero_start", actual);
}

test "mixed multiline and single-line labels snapshot" {
    const alloc = std.testing.allocator;
    const source =
        \\fn eval() {
        \\    let pair = make_pair(
        \\        left,
        \\        right,
        \\    );
        \\    consume(pair);
        \\}
    ;
    const multiline_start = offsetOf(source, "make_pair(");
    const multiline_end = offsetOf(source, ");");
    const consume = spanOf(source, "consume(pair)");
    const labels = [_]Label{
        Label.primary(multiline_start, multiline_end + 1, "pair construction", 0),
        Label.secondary(consume.start, consume.end, "later use", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .@"error",
        .message = "related operations",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "mixed.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "mixed_multiline_and_single_line", actual);
}

test "label without message snapshot" {
    const alloc = std.testing.allocator;
    const source = "return lhs + rhs;";
    const lhs = spanOf(source, "lhs");
    const rhs = spanOf(source, "rhs");
    const labels = [_]Label{
        Label.primary(lhs.start, lhs.end, "", 0),
        Label.secondary(rhs.start, rhs.end, "", 0),
    };
    const diagnostic = Diagnostic{
        .severity = .info,
        .message = "message-less labels",
        .labels = &labels,
        .notes = &.{},
    };

    const actual = try renderDiagnostic(alloc, "empty_messages.mp", source, diagnostic);
    defer alloc.free(actual);

    try snapshot.expectSnapshot(alloc, "labels_without_messages", actual);
}
