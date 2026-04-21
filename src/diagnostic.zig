const std = @import("std");
const sourcefile = @import("sourcefile.zig");
const SourceFile = sourcefile.SourceFile;

pub const Severity = enum {
    Error,
    Warning,
    Info,
};

pub const Label = struct {
    style: enum {
        Primary,
        Secondary,
    },
    start: usize,
    end: usize,
    message: []const u8,
    file: *const SourceFile, // TODO: eventually, replace this with a fileId

    pub fn primary(start: usize, end: usize, message: []const u8, file: *const SourceFile) Label {
        return Label{
            .style = .Primary,
            .start = start,
            .end = end,
            .message = message,
            .file = file,
        };
    }

    pub fn secondary(start: usize, end: usize, message: []const u8, file: *const SourceFile) Label {
        return Label{
            .style = .Secondary,
            .start = start,
            .end = end,
            .message = message,
            .file = file,
        };
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    labels: []const Label,
    notes: []const []const u8,
};
