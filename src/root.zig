const std = @import("std");
pub const SourceFile = @import("sourcefile.zig").SourceFile;
pub const Renderer = @import("renderer.zig").Renderer;
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Label = @import("diagnostic.zig").Label;
pub const Config = @import("config.zig").Config;
pub const Severity = @import("diagnostic.zig").Severity;

pub fn displayDiagnostic(
    diagnostic: Diagnostic,
    sources: []const SourceFile,
    writer: *std.Io.Writer,
    alloc: std.mem.Allocator,
) !void {
    var renderer = Renderer.init(Config.default(), writer);
    try renderer.renderDiagnostic(diagnostic, sources, alloc);
}
