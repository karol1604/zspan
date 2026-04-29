const std = @import("std");

const config = @import("config.zig");
const sourcefile = @import("sourcefile.zig");
const SourceFile = sourcefile.SourceFile;
const utils = @import("utils.zig");

pub const Severity = enum {
    @"error",
    warning,
    info,
};

pub const Label = struct {
    style: enum {
        Primary,
        Secondary,
    },
    start: usize,
    end: usize,
    message: []const u8,
    fileId: usize,

    pub fn primary(start: usize, end: usize, message: []const u8, fileId: usize) Label {
        return Label{
            .style = .Primary,
            .start = start,
            .end = end,
            .message = message,
            .fileId = fileId,
        };
    }

    pub fn secondary(start: usize, end: usize, message: []const u8, fileId: usize) Label {
        return Label{
            .style = .Secondary,
            .start = start,
            .end = end,
            .message = message,
            .fileId = fileId,
        };
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    labels: []const Label,
    notes: []const []const u8,
};
