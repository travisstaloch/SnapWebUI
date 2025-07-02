const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const template_encoder = @import("template_encoder.zig");

pub const HtmlTemplate = template_encoder.EncodedTemplate;

/// DOM node handle type
pub const NodeId = enum(i32) { null = std.math.minInt(i32), _ };

/// DOM event
pub const EventHandler = struct {
    callback: *const Callback,
    ctx: *anyopaque,
    data: usize = 0,

    pub const Callback = fn (*anyopaque, data: usize) anyerror!void;

    pub fn init(callback: *const Callback, ctx: *anyopaque) EventHandler {
        return .{ .callback = callback, .ctx = ctx };
    }

    pub fn initWithData(callback: *const Callback, ctx: *anyopaque, data: usize) EventHandler {
        return .{ .callback = callback, .ctx = ctx, .data = data };
    }

    pub fn format(self: EventHandler, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(
            \\callWasmCallback({}, {}, {})
        , .{ @intFromPtr(self.callback), @intFromPtr(self.ctx), self.data });
    }

    pub const e = init;
    pub const ed = initWithData;
};

pub const eh = EventHandler.init;
pub const ehd = EventHandler.initWithData;

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
    pub fn init(name: []const u8, value: []const u8) Attribute {
        return .{ .name = name, .value = value };
    }
    pub const a = init;
    // unused
    pub fn eql(self: Attribute, other: Attribute) bool {
        return mem.eql(u8, self.name, other.name) and mem.eql(u8, self.value, other.value);
    }
};

pub const Element = @FieldType(Node, "element");

/// A virtual DOM node
pub const Node = union(enum) {
    empty,
    element: struct {
        tag: []const u8,
        attributes: []const Attribute,
        events: []const EventHandler,
        children: []const Node,
    },
    text: []const u8,

    pub fn format(self: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (mem.eql(u8, fmt, "html")) {
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
                const self_closing = mem.eql(u8, element.tag, "br") or
                    mem.eql(u8, element.tag, "hr") or
                    mem.eql(u8, element.tag, "img") or
                    mem.eql(u8, element.tag, "input") or
                    mem.eql(u8, element.tag, "meta") or
                    mem.eql(u8, element.tag, "link");

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
                    try writer.print("{{ .callback = {*}, .ctx = {*} }}", .{ event.callback, event.ctx });
                }
                try writer.writeAll("] }");
            },
            .text => |text| {
                try writer.print("Node.text(\"{s}\")", .{text});
            },
        }
    }

    // unused
    pub fn eql(self: Node, other: Node) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;

        return switch (self) {
            .empty => true,
            .element => |s_el| mem.eql(u8, s_el.tag, other.element.tag) and
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
                return mem.eql(u8, s_text, o_text);
            },
        };
    }
};

/// create virtual element node
pub fn h(
    tag: []const u8,
    attributes: []const Attribute,
    events: []const EventHandler,
    children: []const Node,
) Node {
    assert(tag.len != 0);
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

/// create virtual formatted text node
pub fn tf(buf: []u8, comptime fmt: []const u8, args: anytype) Node {
    const text = std.fmt.bufPrint(buf, fmt, args) catch buf;
    return .{ .text = text };
}

pub fn State(T: type, Subscriber: type) type {
    return struct {
        inner: T,
        subscriber: Subscriber,

        pub const Inner = T;

        pub fn set(self: *@This(), new_state: T) !void {
            self.inner = new_state;
            try self.subscriber.onStateChange();
        }

        ///  allows for in-place modification of complex types
        pub fn getForUpdate(self: *@This()) *T {
            return &self.inner;
        }

        /// signals that the modification is complete
        pub fn didUpdate(self: *@This()) !void {
            try self.subscriber.onStateChange();
        }
    };
}

pub fn useState(
    state: anytype,
    subscriber: anytype,
) State(@TypeOf(state), @TypeOf(subscriber)) {
    return .{ .inner = state, .subscriber = subscriber };
}

/// External JS functions
pub const js = struct {
    pub extern fn querySelector(start: [*]const u8, len: usize) NodeId;
    pub extern fn consoleLog(start: [*]const u8, len: usize) void;
    pub extern fn querySelectorValue(selector_ptr: [*]const u8, selector_len: usize, prop_ptr: [*]const u8, prop_len: usize, buf_ptr: [*]u8, buf_len: usize) usize;
    pub extern fn getElementInnerHTML(selector_ptr: [*]const u8, selector_len: usize, buf_ptr: [*]u8, buf_len: usize) usize;
    pub extern fn captureBacktrace() void;
    pub extern fn printCapturedBacktrace() void;
    pub extern fn setTextContent(node_id: NodeId, text_ptr: [*]const u8, text_len: usize) void;
    // Immediate-mode rendering functions
    pub extern fn beginRender(parent_id: NodeId) void;
    pub extern fn createElementImmediate(tag_ptr: [*]const u8, tag_len: usize) void;
    pub extern fn createTextImmediate(text_ptr: [*]const u8, text_len: usize) void;
    pub extern fn createHtmlImmediate(html_ptr: [*]const u8, html_len: usize) void;
    pub extern fn setAttributeImmediate(name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) void;
    pub extern fn addEventImmediate(event_ptr: [*]const u8, event_len: usize, callback_ptr: usize, ctx_ptr: usize, data: usize) void;
    pub extern fn appendChildImmediate() void;
    pub extern fn endRender() void;
    // Template encoding functions
    pub extern fn encodeTemplate(selector_ptr: [*]const u8, selector_len: usize, buffer_ptr: [*]u8, buffer_len: usize) usize;
    pub extern fn getEncodedTemplateSize(selector_ptr: [*]const u8, selector_len: usize) usize;
    // Animation functions
    pub extern fn requestAnimationFrame(callback_ptr: usize, ctx_ptr: usize) u32;
};

const is_wasm = @import("builtin").cpu.arch == .wasm32;

/// begin creating element immediately in browser DOM
pub fn hiBegin(
    tag: []const u8,
    attributes: []const Attribute,
    events: []const EventHandler,
) void {
    if (!is_wasm) return;
    js.createElementImmediate(tag.ptr, tag.len);

    for (attributes) |attr| {
        js.setAttributeImmediate(attr.name.ptr, attr.name.len, attr.value.ptr, attr.value.len);
    }

    for (events) |event| {
        js.addEventImmediate(event.name.ptr, event.name.len, @intFromPtr(event.callback), @intFromPtr(event.ctx), event.data);
    }
}

/// end creating element and append to parent
pub fn hiEnd() void {
    if (!is_wasm) return;
    js.appendChildImmediate();
}

/// Builder for DOM construction
pub const Builder = struct {
    state: enum { start, elem } = .start,
    /// Start an element with attributes and events
    pub fn elem(
        self: *Builder,
        tag: []const u8,
        attributes: []const Attribute,
        events: []const EventHandler,
    ) *Builder {
        hiBegin(tag, attributes, events);
        self.state = .elem;
        return self;
    }

    /// Add text content
    pub fn text(self: *Builder, txt: []const u8) *Builder {
        ti(txt);
        return self;
    }

    /// Add formatted text content
    pub fn textf(self: *Builder, comptime fmt: []const u8, args: anytype) *Builder {
        var buf: [4096]u8 = undefined;
        const txt = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
        ti(txt);
        return self;
    }

    /// Render children using a function
    pub fn children(self: *Builder, render_fn: fn (*Builder) void) *Builder {
        render_fn(self);
        hiEnd();
        return self;
    }

    /// Render children using a method
    pub fn childrenWith(
        self: *Builder,
        ctx: anytype,
        render_fn: fn (@TypeOf(ctx), *Builder) void,
    ) *Builder {
        render_fn(ctx, self);
        hiEnd();
        return self;
    }

    /// End current element (for elements without children function)
    pub fn end(self: *Builder) *Builder {
        hiEnd();
        return self;
    }
};

/// create element with children immediately (for simple cases)
pub fn hi(
    tag: []const u8,
    attributes: []const Attribute,
    events: []const EventHandler,
    children: []const Node,
) void {
    hiBegin(tag, attributes, events);
    for (children) |child| {
        switch (child) {
            .empty => {},
            .element => |ele| {
                hi(ele.tag, ele.attributes, ele.events, ele.children);
            },
            .text => ti(child.text),
        }
    }
    hiEnd();
}

/// create text node immediately in browser DOM
pub fn ti(text: []const u8) void {
    if (!is_wasm) return;
    js.createTextImmediate(text.ptr, text.len);
    js.appendChildImmediate();
}

/// create formatted text node immediately in browser DOM
pub fn tif(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    ti(text);
}

/// return node_id result from document.querySelector()
pub fn querySelector(selector: []const u8) NodeId {
    return js.querySelector(selector.ptr, selector.len);
}

pub fn querySelectorValue(selector: []const u8, prop: []const u8, buf: []u8) []const u8 {
    const len = js.querySelectorValue(selector.ptr, selector.len, prop.ptr, prop.len, buf.ptr, buf.len);
    return buf[0..len];
}

/// write message to console.log
pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (!is_wasm) return;
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    js.consoleLog(msg.ptr, msg.len);
}

pub fn panicasdf(comptime fmt: []const u8, args: anytype) noreturn {
    if (!is_wasm) return;
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    js.consoleLog(msg.ptr, msg.len);
    @trap();
}

/// unwrap error_union payload or else log and trap
pub fn unwrapErr(error_union: anytype) void {
    if (error_union) |_| {} else |e| {
        log("error: {s}", .{@errorName(e)});
        if (is_wasm) {
            js.captureBacktrace();
            js.printCapturedBacktrace();
        }
    }
}

/// Set text content of a DOM element
pub fn setTextContent(node_id: NodeId, text: []const u8) void {
    if (!is_wasm) return;
    js.setTextContent(node_id, text.ptr, text.len);
}

/// Start animation loop using requestAnimationFrame
pub fn startAnimationLoop(event_handler: EventHandler) void {
    if (!is_wasm) return;
    _ = js.requestAnimationFrame(@intFromPtr(event_handler.callback), @intFromPtr(event_handler.ctx));
}

/// execute callback in zig, passing context pointer
export fn callZigCallback(callback_ptr: usize, ctx_ptr: usize, data: usize) void {
    const callback: *const EventHandler.Callback = @ptrFromInt(callback_ptr);
    unwrapErr(callback(@ptrFromInt(ctx_ptr), data));
}

pub fn querySelectorInnerHTML(selector: []const u8, buf: []u8) [:0]const u8 {
    const len = js.getElementInnerHTML(selector.ptr, selector.len, buf.ptr, buf.len);
    buf[len] = 0;
    return buf[0..len :0];
}

pub const RenderActionCallback = fn (ctx: *anyopaque) anyerror!void;
pub fn RenderableAction(T: type) type {
    return struct {
        action: *const RenderActionCallback,
        ctx: *anyopaque,
        args: T,

        pub const is_snap_renderable_action = {};
    };
}

pub fn renderableAction(
    action: *const RenderActionCallback,
    ctx: *anyopaque,
    args: anytype,
) RenderableAction(@TypeOf(args)) {
    return .{ .action = action, .ctx = ctx, .args = args };
}

pub fn encodeTemplateFromDOM(allocator: mem.Allocator, selector: []const u8) !HtmlTemplate {
    if (!is_wasm) return error.NotWasm;

    const buffer_size = js.getEncodedTemplateSize(selector.ptr, selector.len);
    if (buffer_size == 0) return error.TemplateNotFound;

    const buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    const actual_size = js.encodeTemplate(selector.ptr, selector.len, buffer.ptr, buffer.len);
    if (actual_size == 0) return error.EncodingFailed;
    if (actual_size != buffer_size) return error.EncodingMismatch;

    return template_encoder.deserializeEncodedTemplate(allocator, buffer);
}

pub fn renderEncodedTemplate(node_id: NodeId, template: template_encoder.EncodedTemplate, args: anytype) !void {
    if (!is_wasm) return;
    js.beginRender(node_id);
    try renderEncodedTemplateInner(template, args);
    js.endRender();
}

pub fn renderEncodedTemplateInner(template: template_encoder.EncodedTemplate, args: anytype) !void {
    var buf: [256]u8 = undefined;
    for (template.instructions) |instruction| {
        switch (instruction.tag) {
            .static_tag_open => {
                const tag_ref = template.tag_opens[instruction.payload_index];
                const tag = tag_ref.slice(template.strings);
                js.createElementImmediate(tag.ptr, tag.len);
            },
            .static_tag_close => {
                js.appendChildImmediate();
            },
            .static_text => {
                const text_ref = template.texts[instruction.payload_index];
                const text = text_ref.slice(template.strings);
                js.createTextImmediate(text.ptr, text.len);
                js.appendChildImmediate();
            },
            .static_attribute => {
                const attr_refs = template.static_attrs[instruction.payload_index];
                const name = attr_refs[0].slice(template.strings);
                const value = attr_refs[1].slice(template.strings);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_text => {
                const field_ref = template.dyn_texts[instruction.payload_index];
                const field_name = field_ref.slice(template.strings);
                try renderDynamicTextNodeFromField(field_name, args);
            },
            .static_dyn_attr => {
                const attr_refs = template.static_dyn_attrs[instruction.payload_index];
                const name = attr_refs[0].slice(template.strings);
                const field_name = attr_refs[1].slice(template.strings);
                const value = try resolveDynamicStringFromField(&buf, field_name, args);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_static_attr => {
                const attr_refs = template.dyn_static_attrs[instruction.payload_index];
                const field_name = attr_refs[0].slice(template.strings);
                const value = attr_refs[1].slice(template.strings);
                var buf2: [256]u8 = undefined;
                const name = try resolveDynamicStringFromField(&buf2, field_name, args);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_dyn_attr => {
                const attr_refs = template.dyn_dyn_attrs[instruction.payload_index];
                const name_field = attr_refs[0].slice(template.strings);
                const value_field = attr_refs[1].slice(template.strings);
                const name = try resolveDynamicStringFromField(&buf, name_field, args);
                var buf2: [256]u8 = undefined;
                const value = try resolveDynamicStringFromField(&buf2, value_field, args);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_event => {
                const event_refs = template.dyn_events[instruction.payload_index];
                const event_name = event_refs[0].slice(template.strings);
                const handler_field = event_refs[1].slice(template.strings);
                const event = try resolveDynamicEventHandlerFromField(handler_field, args);
                js.addEventImmediate(event_name.ptr, event_name.len, @intFromPtr(event.callback), @intFromPtr(event.ctx), event.data);
            },
        }
    }
}

// Helper functions for the new template system
fn resolveDynamicStringFromField(buf: []u8, field_name: []const u8, args: anytype) ![]const u8 {
    const Fe = std.meta.FieldEnum(@TypeOf(args));
    switch (std.meta.stringToEnum(Fe, field_name) orelse {
        log("template field '{s}' missing from args", .{field_name});
        return error.TemplateNotFound;
    }) {
        inline else => |f| {
            const field = @field(args, @tagName(f));
            return switch (@typeInfo(@TypeOf(field))) {
                .int => try std.fmt.bufPrint(buf, "{}", .{field}),
                .pointer => |p| if (p.size == .slice) if (p.child == u8)
                    field
                else {
                    log("cannot use type {s} as string for field '{s}'", .{ @typeName(@TypeOf(field)), field_name });
                    return error.InvalidTemplateArgumentType;
                } else {
                    log("cannot use type {s} for field '{s}'", .{ @typeName(@TypeOf(field)), field_name });
                    return error.InvalidTemplateArgumentType;
                },
                else => |info| {
                    log("cannot use type {s} as string for field '{s}'", .{ @tagName(info), field_name });
                    return error.InvalidTemplateArgumentType;
                },
            };
        },
    }
}

fn resolveDynamicEventHandlerFromField(field_name: []const u8, args: anytype) !EventHandler {
    const Fe = std.meta.FieldEnum(@TypeOf(args));
    switch (std.meta.stringToEnum(Fe, field_name) orelse {
        log("template field '{s}' missing from args", .{field_name});
        return error.TemplateFieldNotFound;
    }) {
        inline else => |f| {
            const field = @field(args, @tagName(f));
            const Field = @TypeOf(field);
            if (Field != EventHandler) {
                log("field '{s}' has type {s}, expected EventHandler", .{ field_name, @typeName(Field) });
                return error.InvalidTemplateArgumentType;
            }
            return field;
        },
    }
}

fn renderDynamicTextNodeFromField(field_name: []const u8, args: anytype) !void {
    const Fe = std.meta.FieldEnum(@TypeOf(args));
    switch (std.meta.stringToEnum(Fe, field_name) orelse {
        log("template field '{s}' missing from args", .{field_name});
        return error.TemplateFieldNotFound;
    }) {
        inline else => |f| {
            const field = @field(args, @tagName(f));
            switch (@typeInfo(@TypeOf(field))) {
                .int => tif("{}", .{field}),
                .pointer => |p| if (p.size == .slice) {
                    if (p.child == u8) {
                        js.createTextImmediate(field.ptr, field.len);
                        js.appendChildImmediate();
                    } else {
                        log("field '{s}' of type {s} cannot be rendered as a text node", .{ field_name, @typeName(@TypeOf(field)) });
                        return error.InvalidTemplateArgumentType;
                    }
                } else {
                    log("field '{s}' of type {s} cannot be rendered as a text node", .{ field_name, @typeName(@TypeOf(field)) });
                    return error.InvalidTemplateArgumentType;
                },
                .@"struct" => if (@hasDecl(@TypeOf(field), "is_snap_renderable")) {
                    renderEncodedTemplateInner(field.template, field.args);
                } else if (@hasDecl(@TypeOf(field), "is_snap_renderable_action")) {
                    try field.action(field.ctx);
                } else {
                    log("field '{s}' of type {s} cannot be rendered as a text node", .{ field_name, @typeName(@TypeOf(field)) });
                    return error.InvalidTemplateArgumentType;
                },
                else => |info| {
                    log("field '{s}' of type {s} cannot be rendered as a text node", .{ field_name, @tagName(info) });
                    return error.InvalidTemplateArgumentType;
                },
            }
        },
    }
}

// Update the Renderable type to work with EncodedTemplate
pub fn EncodedRenderable(T: type) type {
    return struct {
        template: template_encoder.EncodedTemplate,
        args: T,

        pub const is_snap_renderable = {};
    };
}

pub fn encodedRenderable(template: template_encoder.EncodedTemplate, args: anytype) EncodedRenderable(@TypeOf(args)) {
    return .{ .template = template, .args = args };
}
