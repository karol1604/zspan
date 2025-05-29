pub const Config = struct {
    displayMode: DisplayMode,
    charset: Charset,

    pub fn default() Config {
        return .{
            .displayMode = .Verbose,
            .charset = Charset.ascii(),
        };
    }
};

const DisplayMode = enum {
    Minimal,
    Verbose,
};

const Charset = struct {
    headerStart: []const u8,
    border: []const u8,
    noteMarker: []const u8,
    primaryUnderline: []const u8,
    secondaryUnderline: []const u8,
    // ... and other fields

    pub fn utf8() Charset {
        return .{
            .headerStart = "┌─",
            .border = "│",
            .noteMarker = "=",
            .primaryUnderline = "^",
            .secondaryUnderline = "~",
        };
    }

    pub fn ascii() Charset {
        return .{
            .headerStart = "-->",
            .border = "|",
            .noteMarker = "=",
            .primaryUnderline = "^",
            .secondaryUnderline = "~",
        };
    }
};
