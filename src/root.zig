const std = @import("std");
pub const SourceFile = @import("sourcefile.zig").SourceFile;
pub const Renderer = @import("renderer.zig").Renderer;
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Label = @import("diagnostic.zig").Label;
pub const Config = @import("config.zig").Config;

pub fn displayDiagnostic(diagnostic: Diagnostic, source: SourceFile, writer: *std.io.Writer) !void {
    var renderer = Renderer.init(Config.default(), writer);
    try renderer.renderDiagnostic(diagnostic, source);
}
