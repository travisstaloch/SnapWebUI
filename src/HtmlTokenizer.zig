const std = @import("std");
const assert = std.debug.assert;

pub const Tokenizer = @This();

index: u32 = 0,
state: State = .start,

pub const Span = struct {
    start: u32,
    end: u32,

    pub const zero: Span = .{ .start = 0, .end = 0 };

    pub fn slice(loc: Span, s: [:0]const u8) []const u8 {
        return s[loc.start..loc.end];
    }
};

pub const Token = struct {
    tag: Tag,
    span: Span,

    pub const Tag = enum(u8) {
        text,
        tag_name,
        tag_end_name,
        attr_name,
        attr_value,
        tag_self_close,
        comment,
        doctype,
        eof,
        invalid,
    };

    pub fn src(t: Token, s: [:0]const u8) []const u8 {
        return t.span.slice(s);
    }
};

pub fn init(src: [:0]const u8) !Tokenizer {
    if (src.len > 0 and src[src.len - 1] != 0) return error.InvalidInput;
    if (!std.unicode.utf8ValidateSlice(src)) return error.InvalidUTF8;
    return Tokenizer{ .src = src };
}

pub fn next(self: *Tokenizer, src: [:0]const u8) Token {
    return self.nextInner(src);
}

fn srcAt(self: *Tokenizer, src: [:0]const u8, offset: u32) u8 {
    const i = self.index + offset;
    if (i >= src.len) return 0;
    return src[i];
}

const State = enum {
    start,
    text,
    tag_start,
    tag_name,
    tag_end_name,
    tag_body,
    attr_name,
    attr_value,
    attr_value_quoted,
    comment,
    doctype,
    invalid,
};

fn tx(self: *Tokenizer, comptime state: State, inc: u32, token: *Token) State {
    _ = token; // autofix
    // if (@intFromEnum(state) < @intFromEnum(State.start)) {
    //     const t: Token.Tag = @enumFromInt(@intFromEnum(state));
    //     if (token.tag != t) {
    //         token.span.start = self.index;
    //         token.tag = t;
    //     }
    // }
    // token.span.start = self.index;
    self.index += inc;
    return state;
}

const is_wasm = @import("builtin").cpu.arch == .wasm32;
fn nextInner(self: *Tokenizer, src: [:0]const u8) Token {
    const start = @min(src.len, self.index);
    var r: Token = .{ .tag = .invalid, .span = .{ .start = start, .end = start } };

    // Skip whitespace
    while (std.ascii.isWhitespace(self.srcAt(src, 0))) {
        self.index += 1;
    }
    r.span.start = self.index;

    switch (self.state) {
        inline else => |tag| {
            _ = tag; // autofix
            // if (!is_wasm) std.debug.print("{s} {c}\n", .{ @tagName(tag), self.srcAt(src, 0) });
            state: switch (self.state) {
                .start => switch (self.srcAt(src, 0)) {
                    0 => r.tag = .eof,
                    '<' => continue :state self.tx(.tag_start, 1, &r),
                    else => continue :state self.tx(.text, 0, &r),
                },
                .text => {
                    r.span.start = self.index;
                    while (self.srcAt(src, 0) != '<' and self.srcAt(src, 0) != 0) {
                        self.index += 1;
                    }
                    r.tag = .text;
                    r.span.end = @min(self.index, src.len);
                    switch (self.srcAt(src, 0)) {
                        '<' => self.state = .tag_start,
                        0 => self.state = .start,
                        else => unreachable,
                    }
                    return r;
                },
                .tag_start => switch (self.srcAt(src, 0)) {
                    '<' => {
                        self.index += 1;
                        continue :state .tag_start;
                    },
                    '!' => {
                        if (std.mem.startsWith(u8, src[self.index..], "!--")) {
                            continue :state self.tx(.comment, 3, &r);
                        } else if (std.mem.startsWith(u8, src[self.index..], "!DOCTYPE")) {
                            continue :state self.tx(.doctype, 8, &r);
                        } else {
                            continue :state self.tx(.invalid, 1, &r);
                        }
                    },
                    '/' => {
                        continue :state self.tx(.tag_end_name, 1, &r);
                    },
                    else => continue :state self.tx(.tag_name, 0, &r),
                },
                .tag_name => {
                    r.span.start = self.index;
                    while (std.mem.indexOfScalar(u8, " \n\r\t>/\x00", self.srcAt(src, 0)) == null) {
                        self.index += 1;
                    }
                    r.tag = .tag_name;
                    r.span.end = self.index;
                    self.state = .tag_body;
                    return r;
                },
                .tag_end_name => {
                    r.span.start = self.index;
                    while (std.mem.indexOfScalar(u8, " \n\r\t>/\x00", self.srcAt(src, 0)) == null) {
                        self.index += 1;
                    }
                    r.tag = .tag_end_name;
                    r.span.end = self.index;
                    self.state = .start;
                    while (std.ascii.isWhitespace(self.srcAt(src, 0))) {
                        self.index += 1;
                    }
                    if (self.srcAt(src, 0) == '>') {
                        self.index += 1;
                    }
                    return r;
                },
                .tag_body => {
                    while (std.ascii.isWhitespace(self.srcAt(src, 0))) {
                        self.index += 1;
                    }
                    if (self.srcAt(src, 0) == '>') {
                        self.index += 1;
                        continue :state .start;
                    } else if (self.srcAt(src, 0) == '/' and self.srcAt(src, 1) == '>') {
                        r.tag = .tag_self_close;
                        self.index += 2;
                        self.state = .start;
                    } else {
                        continue :state self.tx(.attr_name, 0, &r);
                    }
                },
                .attr_name => {
                    while (std.mem.indexOfScalar(u8, " \n\r\t=>/\x00", self.srcAt(src, 0)) == null) {
                        self.index += 1;
                    }
                    r.tag = .attr_name;
                    // Skip whitespace and the equals sign
                    while (std.ascii.isWhitespace(self.srcAt(src, 0))) {
                        self.index += 1;
                    }
                    if (self.srcAt(src, 0) == '=') {
                        const end = self.index;
                        self.index += 1;
                        while (std.ascii.isWhitespace(self.srcAt(src, 0))) {
                            self.index += 1;
                        }
                        self.state = .attr_value;
                        r.span.end = @min(end, src.len);
                        return r;
                    } else {
                        // Attribute without a value
                        self.state = .tag_body;
                    }
                },
                .attr_value => switch (self.srcAt(src, 0)) {
                    '"' => {
                        r.span.start += 1; // exclude quote
                        continue :state self.tx(.attr_value_quoted, 1, &r);
                    },
                    else => {
                        while (std.mem.indexOfScalar(u8, " \n\r\t>\x00", self.srcAt(src, 0)) == null) {
                            self.index += 1;
                        }
                        r.tag = .attr_value;
                        self.state = .tag_body;
                    },
                },
                .attr_value_quoted => {
                    while (self.srcAt(src, 0) != '"' and self.srcAt(src, 0) != 0) {
                        self.index += 1;
                    }
                    r.tag = .attr_value;
                    r.span.end = @min(self.index, src.len);
                    self.index += 1; // Skip closing quote
                    self.state = .tag_body;
                    return r;
                },
                .comment => if (std.mem.indexOf(u8, src[self.index..], "-->")) |ep| {
                    self.index += @intCast(ep);
                    r.tag = .comment;
                    self.index += 3;
                } else {
                    self.index = @intCast(src.len);
                    r.tag = .invalid;
                },
                .doctype => {
                    while (self.srcAt(src, 0) != '>' and self.srcAt(src, 0) != 0) {
                        self.index += 1;
                    }
                    r.tag = .doctype;
                    if (self.srcAt(src, 0) == '>') self.index += 1;
                },

                .invalid => {
                    while (self.srcAt(src, 0) != 0) {
                        self.index += 1;
                    }
                },
            }

            r.span.end = @min(self.index, src.len);
            return r;
        },
    }
}
