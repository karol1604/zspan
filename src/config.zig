const std = @import("std");
const Severity = @import("diagnostic.zig").Severity;

const Color = std.Io.Terminal.Color;

pub const Config = struct {
    displayMode: enum {
        Minimal,
        Verbose,
    },
    charset: Charset,
    colorMode: std.Io.Terminal.Mode,
    colors: ColorSet,

    pub fn default() Config {
        return .{
            .displayMode = .Verbose,
            .charset = Charset.utf8(),
            .colorMode = .escape_codes,
            .colors = ColorSet.default(),
        };
    }
};

const ColorSet = struct {
    headerError: Color,
    headerWarning: Color,
    headerInfo: Color,

    primaryLabelError: Color,
    primaryLabelWarning: Color,
    primaryLabelInfo: Color,
    secondaryLabel: Color,

    border: Color,
    noteMarker: Color,
    lineNumber: Color,

    pub fn default() ColorSet {
        return .{
            .headerError = .red,
            .headerWarning = .yellow,
            .headerInfo = .cyan,

            .primaryLabelError = .red,
            .primaryLabelWarning = .yellow,
            .primaryLabelInfo = .cyan,
            .secondaryLabel = .blue,

            .border = .blue,
            .noteMarker = .blue,
            .lineNumber = .blue,
        };
    }

    pub fn header(self: ColorSet, sev: Severity) Color {
        return switch (sev) {
            .@"error" => self.headerError,
            .warning => self.headerWarning,
            .info => self.headerInfo,
        };
    }
};

const Charset = struct {
    headerStart: []const u8,
    border: []const u8,
    connector: []const u8,
    noteMarker: []const u8,
    primaryUnderline: []const u8,
    secondaryUnderline: []const u8,
    borderBreak: []const u8,
    // ... and other fields

    pub fn utf8() Charset {
        return .{
            .headerStart = "┏━━━",
            .border = "┃",
            .connector = "│",
            // .noteMarker = "•",
            // .noteMarker = "╾",
            .noteMarker = "=",
            .borderBreak = "┇",
            .primaryUnderline = "^",
            .secondaryUnderline = "─",
        };
    }

    pub fn ascii() Charset {
        return .{
            .headerStart = "-->",
            .border = "|",
            .connector = "|",
            .borderBreak = ":",
            .noteMarker = "=",
            .primaryUnderline = "^",
            .secondaryUnderline = "-",
        };
    }
};
