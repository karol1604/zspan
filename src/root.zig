const std = @import("std");

const fileModule = @import("source-file.zig");
pub const SourceFile = fileModule.SourceFile;
pub const SourceFiles = fileModule.SourceFiles;
pub const Renderer = @import("renderer.zig").Renderer;
pub const Config = @import("config.zig").Config;
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const Label = @import("diagnostic.zig").Label;

pub fn displayDiagnostic(diagnostic: *const Diagnostic, files: *const SourceFiles, config: Config, writer: std.io.AnyWriter) !void {
    const renderer = Renderer.init(writer, config);

    switch (config.displayMode) {
        .Minimal => try renderer.renderMinimalDiagnostic(diagnostic, files),
        .Verbose => try renderer.renderVerboseDiagnostic(diagnostic, files),
    }
}

// const VerboseDiagnostic = struct {
//     diagnostic: *const Diagnostic,
//     config: Config,
//
//     pub fn init(diagnostic: *const Diagnostic, config: Config) VerboseDiagnostic {
//         return .{
//             .diagnostic = diagnostic,
//             .config = config,
//         };
//     }
// };
//
// const MinimalDiagnostic = struct {
//     diagnostic: *const Diagnostic,
//
//     pub fn init(diagnostic: *const Diagnostic) MinimalDiagnostic {
//         return .{ .diagnostic = diagnostic };
//     }
// };
