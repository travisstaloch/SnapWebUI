const std = @import("std");

/// DOM node handle type
pub const NodeId = enum(i32) { null = std.math.minInt(i32), _ };

/// DOM event
pub const EventHandler = struct {
    name: []const u8,
    callback: *const Callback,
    ctx: *anyopaque,

    pub const Callback = fn (*anyopaque) anyerror!void;
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    pub fn init(name: []const u8, value: []const u8) Attribute {
        return .{ .name = name, .value = value };
    }
    pub const a = init;
    pub fn eql(self: Attribute, other: Attribute) bool {
        return std.mem.eql(u8, self.name, other.name) and std.mem.eql(u8, self.value, other.value);
    }
};

/// A virtual DOM node
pub const Node = union(enum) {
    empty,
    element: struct {
        tag: []const u8,
        attributes: []const Attribute,
        children: []const Node,
        events: []const EventHandler,
    },
    text: []const u8,

    pub fn format(self: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (std.mem.eql(u8, fmt, "html")) {
            try self.formatHtml(writer);
        } else {
            try self.formatDefault(writer, options);
        }
    }

    fn formatHtml(self: Node, writer: anytype) !void {
        switch (self) {
            .empty => {
                // Empty nodes produce no HTML output
            },
            .element => |element| {
                // Opening tag
                try writer.writeAll("<");
                try writer.writeAll(element.tag);

                // Attributes
                for (element.attributes) |attr| {
                    try writer.writeAll(" ");
                    try writer.writeAll(attr.name);
                    try writer.writeAll("=\"");
                    try writer.writeAll(attr.value);
                    try writer.writeAll("\"");
                }

                // Check if it's a self-closing tag
                const self_closing = std.mem.eql(u8, element.tag, "br") or
                    std.mem.eql(u8, element.tag, "hr") or
                    std.mem.eql(u8, element.tag, "img") or
                    std.mem.eql(u8, element.tag, "input") or
                    std.mem.eql(u8, element.tag, "meta") or
                    std.mem.eql(u8, element.tag, "link");

                if (self_closing and element.children.len == 0) {
                    try writer.writeAll(" />");
                } else {
                    try writer.writeAll(">");

                    // Children
                    for (element.children) |child| {
                        try child.formatHtml(writer);
                    }

                    // Closing tag
                    try writer.writeAll("</");
                    try writer.writeAll(element.tag);
                    try writer.writeAll(">");
                }
            },
            .text => |text| {
                // Escape HTML entities in text content
                for (text) |char| {
                    switch (char) {
                        '<' => try writer.writeAll("&lt;"),
                        '>' => try writer.writeAll("&gt;"),
                        '&' => try writer.writeAll("&amp;"),
                        '"' => try writer.writeAll("&quot;"),
                        '\'' => try writer.writeAll("&#39;"),
                        else => try writer.writeByte(char),
                    }
                }
            },
        }
    }

    fn formatDefault(self: Node, writer: anytype, options: std.fmt.FormatOptions) !void {
        switch (self) {
            .empty => {
                try writer.writeAll("Node.empty");
            },
            .element => |element| {
                try writer.writeAll("Node.element{ .tag = \"");
                try writer.writeAll(element.tag);
                try writer.writeAll("\", .attributes = [");
                for (element.attributes, 0..) |attr, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{{ .name = \"{s}\", .value = \"{s}\" }}", .{ attr.name, attr.value });
                }
                try writer.writeAll("], .children = [");
                for (element.children, 0..) |child, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try child.formatDefault(writer, options);
                }
                try writer.writeAll("], .events = [");
                for (element.events, 0..) |event, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{{ .name = \"{s}\", .callback = {*}, .ctx = {*} }}", .{ event.name, event.callback, event.ctx });
                }
                try writer.writeAll("] }");
            },
            .text => |text| {
                try writer.print("Node.text(\"{s}\")", .{text});
            },
        }
    }

    // pub fn format(self: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    //     _ = fmt; // autofix

    //     switch (self) {
    //         .empty => {
    //             try writer.writeAll("Node.empty");
    //         },
    //         .element => |element| {
    //             try writer.writeAll("Node.element{ .tag = \"");
    //             try writer.writeAll(element.tag);
    //             try writer.writeAll("\", .attributes = [");
    //             for (element.attributes, 0..) |attr, i| {
    //                 if (i > 0) try writer.writeAll(", ");
    //                 try writer.print("{{ .name = \"{s}\", .value = \"{s}\" }}", .{ attr.name, attr.value });
    //             }
    //             try writer.writeAll("], .children = [");
    //             for (element.children, 0..) |child, i| {
    //                 if (i > 0) try writer.writeAll(", ");
    //                 try child.format("", options, writer);
    //             }
    //             try writer.writeAll("], .events = [");
    //             for (element.events, 0..) |event, i| {
    //                 if (i > 0) try writer.writeAll(", ");
    //                 try writer.print("{{ .name = \"{s}\", .callback = {*}, .ctx = {*} }}", .{ event.name, event.callback, event.ctx });
    //             }
    //             try writer.writeAll("] }");
    //         },
    //         .text => |text| {
    //             try writer.print("Node.text(\"{s}\")", .{text});
    //         },
    //     }
    // }

    pub fn eql(self: Node, other: Node) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;

        return switch (self) {
            .empty => true,
            .element => |s_el| std.mem.eql(u8, s_el.tag, other.element.tag) and
                s_el.attributes.len == other.element.attributes.len and
                for (s_el.attributes, other.element.attributes) |s_attr, o_attr| {
                    if (!s_attr.eql(o_attr)) break false;
                } else true and
                    s_el.children.len == other.element.children.len and
                    for (s_el.children, other.element.children) |s_child, o_child| {
                        if (!s_child.eql(o_child)) break false;
                    } else true,
            // TODO: Compare events?
            .text => |s_text| {
                const o_text = other.text;
                return std.mem.eql(u8, s_text, o_text);
            },
        };
    }
};

/// create virtual element node
pub fn h(
    tag: []const u8,
    attributes: []const Attribute,
    children: []const Node,
    events: []const EventHandler,
) Node {
    return .{ .element = .{
        .tag = tag,
        .attributes = attributes,
        .children = children,
        .events = events,
    } };
}

/// create virtual text node
pub fn t(text: []const u8) Node {
    return .{ .text = text };
}

pub fn State(T: type, Subscriber: type) type {
    return struct {
        inner: T,
        subscriber: Subscriber,

        pub fn set(self: *@This(), new_state: T) !void {
            self.inner = new_state;
            try self.invalidate();
        }

        pub fn invalidate(self: *@This()) !void {
            try self.subscriber.updateView(self.inner);
        }
    };
}

pub fn useState(
    state: anytype,
    subscriber: anytype,
) State(@TypeOf(state), @TypeOf(subscriber)) {
    return .{ .inner = state, .subscriber = subscriber };
}
