const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
pub const HtmlTokenizer = @import("HtmlTokenizer.zig");

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

/// External JS functions
pub const js = struct {
    pub extern fn querySelector(start: [*]const u8, len: usize) NodeId;
    pub extern fn consoleLog(start: [*]const u8, len: usize) void;
    pub extern fn querySelectorValue(selector_ptr: [*]const u8, selector_len: usize, prop_ptr: [*]const u8, prop_len: usize, buf_ptr: [*]u8, buf_len: usize) usize;
    pub extern fn getElementInnerHTML(selector_ptr: [*]const u8, selector_len: usize, buf_ptr: [*]u8, buf_len: usize) usize;
    pub extern fn captureBacktrace() void;
    pub extern fn printCapturedBacktrace() void;
    // Immediate-mode rendering functions
    pub extern fn beginRender(parent_id: NodeId) void;
    pub extern fn createElementImmediate(tag_ptr: [*]const u8, tag_len: usize) void;
    pub extern fn createTextImmediate(text_ptr: [*]const u8, text_len: usize) void;
    pub extern fn createHtmlImmediate(html_ptr: [*]const u8, html_len: usize) void;
    pub extern fn setAttributeImmediate(name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) void;
    pub extern fn addEventImmediate(event_ptr: [*]const u8, event_len: usize, callback_ptr: usize, ctx_ptr: usize, data: usize) void;
    pub extern fn appendChildImmediate() void;
    pub extern fn endRender() void;
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

pub fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    if (!is_wasm) return;
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    js.consoleLog(msg.ptr, msg.len);
    @trap();
}

fn ErrUnionPayload(eu: type) type {
    return switch (@typeInfo(eu)) {
        .error_union => |u| u.payload,
        else => unreachable,
    };
}

/// unwrap error_union payload or else log and trap
pub fn unwrapErr(error_union: anytype) ErrUnionPayload(@TypeOf(error_union)) {
    return error_union catch |e| {
        log("error: {s}", .{@errorName(e)});
        if (is_wasm)
            js.printCapturedBacktrace();
        @trap();
    };
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

// TODO StaticStringMap
fn isSelfClosingTag(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "area") or
        std.mem.eql(u8, tag, "base") or
        std.mem.eql(u8, tag, "br") or
        std.mem.eql(u8, tag, "col") or
        std.mem.eql(u8, tag, "embed") or
        std.mem.eql(u8, tag, "hr") or
        std.mem.eql(u8, tag, "img") or
        std.mem.eql(u8, tag, "input") or
        std.mem.eql(u8, tag, "link") or
        std.mem.eql(u8, tag, "meta") or
        std.mem.eql(u8, tag, "param") or
        std.mem.eql(u8, tag, "source") or
        std.mem.eql(u8, tag, "track") or
        std.mem.eql(u8, tag, "wbr");
}

pub fn Renderable(T: type) type {
    return struct {
        template: ParsedTemplate,
        args: T,

        pub const is_snap_renderable = {};
    };
}

pub fn renderable(template: ParsedTemplate, args: anytype) Renderable(@TypeOf(args)) {
    return .{ .template = template, .args = args };
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

pub fn renderTemplate(node_id: NodeId, r: anytype) void {
    if (!is_wasm) return;
    js.beginRender(node_id);
    renderTemplateInner(r);
    js.endRender();

    // const html = unwrapErr(std.fmt.allocPrint(allocator, template, args));
    // js.beginRender(node_id);
    // js.createHtmlImmediate(html.ptr, html.len);
    // js.appendChildImmediate();
    // js.endRender();
}

const Span = HtmlTokenizer.Span;

fn resolveDynamicString(buf: []u8, spec_span: Span, r: anytype) ![]const u8 {
    var specname = spec_span.slice(r.template.src);
    if (specname.len >= 2 and specname[0] == '{' and specname[specname.len - 1] == '}') {
        specname = specname[1 .. specname.len - 1];
    }

    const Fe = std.meta.FieldEnum(@TypeOf(r.args));
    switch (std.meta.stringToEnum(Fe, specname) orelse
        panic("template field '{s}' missing from args", .{specname})) {
        inline else => |f| {
            const field = @field(r.args, @tagName(f));
            return switch (@typeInfo(@TypeOf(field))) {
                .int => try std.fmt.bufPrint(buf, "{}", .{field}),
                .pointer => |p| if (p.size == .slice) if (p.child == u8)
                    field
                else {
                    panic("cannot use type {s} as string for field '{s}'", .{ @typeName(@TypeOf(field)), specname });
                } else {
                    panic("cannot use type {s} for field '{s}'", .{ @typeName(@TypeOf(field)), specname });
                },
                else => |info| panic("cannot use type {s} as string for field '{s}'", .{ @tagName(info), specname }),
            };
        },
    }
}

fn resolveDynamicEventHandler(spec_span: Span, r: anytype) !EventHandler {
    var specname = spec_span.slice(r.template.src);
    // Remove curly braces if present
    if (specname.len >= 2 and specname[0] == '{' and specname[specname.len - 1] == '}') {
        specname = specname[1 .. specname.len - 1];
    }
    // Remove "eh__" prefix
    if (mem.startsWith(u8, specname, "eh__")) specname = specname[4..];

    const Fe = std.meta.FieldEnum(@TypeOf(r.args));
    switch (std.meta.stringToEnum(Fe, specname) orelse
        panic("template field '{s}' missing from args", .{specname})) {
        inline else => |f| {
            const field = @field(r.args, @tagName(f));
            const Field = @TypeOf(field);
            if (Field != EventHandler) {
                panic("field '{s}' has type {s}, expected EventHandler", .{ specname, @typeName(Field) });
            }
            return field;
        },
    }
}

fn renderDynamicTextNode(spec_span: Span, r: anytype) !void {
    const specname = spec_span.slice(r.template.src);
    const Fe = std.meta.FieldEnum(@TypeOf(r.args));
    switch (std.meta.stringToEnum(Fe, specname) orelse
        panic("template field '{s}' missing from args", .{specname})) {
        inline else => |f| {
            const field = @field(r.args, @tagName(f));
            switch (@typeInfo(@TypeOf(field))) {
                .int => tif("{}", .{field}),
                .pointer => |p| if (p.size == .slice) {
                    if (p.child == u8) {
                        js.createTextImmediate(field.ptr, field.len);
                        js.appendChildImmediate();
                    } else {
                        panic("field '{s}' of type {s} cannot be rendered as a text node", .{ specname, @typeName(@TypeOf(field)) });
                    }
                } else panic("field '{s}' of type {s} cannot be rendered as a text node", .{ specname, @typeName(@TypeOf(field)) }),
                .@"struct" => if (@hasDecl(@TypeOf(field), "is_snap_renderable")) {
                    renderTemplateInner(field);
                } else if (@hasDecl(@TypeOf(field), "is_snap_renderable_action")) {
                    try field.action(field.ctx);
                } else panic("field '{s}' of type {s} cannot be rendered as a text node", .{ specname, @typeName(@TypeOf(field)) }),
                else => |info| panic("field '{s}' of type {s} cannot be rendered as a text node", .{ specname, @tagName(info) }),
            }
        },
    }
}

pub fn renderTemplateInner(r: anytype) void {
    var buf: [256]u8 = undefined;
    for (r.template.instructions) |ri| {
        switch (ri) {
            .static_tag_open => |span| {
                const tag = span.slice(r.template.src);
                js.createElementImmediate(tag.ptr, tag.len);
            },
            .static_tag_close => {
                js.appendChildImmediate();
            },
            .self_closing_tag => {
                js.appendChildImmediate();
            },
            .static_text => |span| {
                const text = span.slice(r.template.src);
                js.createTextImmediate(text.ptr, text.len);
                js.appendChildImmediate();
            },
            .static_attribute => |attr| {
                const name = attr[0].slice(r.template.src);
                const value = attr[1].slice(r.template.src);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_text => |span| {
                unwrapErr(renderDynamicTextNode(span, r));
            },
            .static_dyn_attr => |spans| {
                const name = spans[0].slice(r.template.src);
                const value = spans[1];
                const value_res = unwrapErr(resolveDynamicString(&buf, value, r));
                js.setAttributeImmediate(name.ptr, name.len, value_res.ptr, value_res.len);
            },
            .dyn_static_attr => |spans| {
                const name = unwrapErr(resolveDynamicString(&buf, spans[0], r));
                const value = spans[1].slice(r.template.src);
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_dyn_attr => |spans| {
                const name = unwrapErr(resolveDynamicString(&buf, spans[0], r));
                var buf2: [256]u8 = undefined;
                const value = unwrapErr(resolveDynamicString(&buf2, spans[1], r));
                js.setAttributeImmediate(name.ptr, name.len, value.ptr, value.len);
            },
            .dyn_event => |spans| {
                const attr_name_span = spans[0];
                const event_handler_span = spans[1];

                const attr_name = attr_name_span.slice(r.template.src);
                const event_name = if (mem.startsWith(u8, attr_name, "on")) attr_name[2..] else attr_name;

                const event = unwrapErr(resolveDynamicEventHandler(event_handler_span, r));
                js.addEventImmediate(event_name.ptr, event_name.len, @intFromPtr(event.callback), @intFromPtr(event.ctx), event.data);
            },
        }
    }
}

pub const RenderInstruction = union(enum) {
    // For static parts of the template
    static_tag_open: Span,
    static_tag_close,
    self_closing_tag,
    static_text: Span,
    static_attribute: [2]Span,

    // dynamic parts reference `args` tuple by names
    dyn_text: Span,
    /// name is static, value is dynamic
    static_dyn_attr: [2]Span,
    /// name is dynamic, value is static
    dyn_static_attr: [2]Span,
    dyn_dyn_attr: [2]Span,
    dyn_event: [2]Span,
};

pub const ParsedTemplate = struct {
    src: [:0]const u8,
    instructions: []RenderInstruction,
};

// Helper function to process and append pending attributes

fn processPendingAttribute(
    res_list: *std.ArrayList(RenderInstruction),
    attr_name: ?Span,
    attr_value: ?Span,
    src: [:0]const u8,
) !void {
    if (attr_name) |name_span| {
        const is_dyn_name = src[name_span.start] == '{' and src[name_span.end - 1] == '}';
        const is_dyn_value = if (attr_value) |v|
            src[v.start] == '{' and src[v.end - 1] == '}'
        else
            false;

        const inst: RenderInstruction = if (is_dyn_name and is_dyn_value)
            .{ .dyn_dyn_attr = .{ name_span, attr_value.? } }
        else if (!is_dyn_name and is_dyn_value)
            if (mem.startsWith(u8, attr_value.?.slice(src), "{eh__"))
                .{ .dyn_event = .{ name_span, attr_value.? } }
            else
                .{ .static_dyn_attr = .{ name_span, attr_value.? } }
        else if (is_dyn_name and !is_dyn_value)
            .{ .dyn_static_attr = .{ name_span, if (attr_value) |v|
                v
            else
                .{ .start = 0, .end = 0 } } }
        else
            .{ .static_attribute = .{ name_span, if (attr_value) |v|
                v
            else
                .{ .start = 0, .end = 0 } } };

        try res_list.append(inst);
    }
}

pub fn parseTemplate(allocator: mem.Allocator, src: [:0]const u8) !ParsedTemplate {
    var res = std.ArrayList(RenderInstruction).init(allocator);
    errdefer res.deinit();
    var tokenizer = HtmlTokenizer{};
    var last_attr_name: ?Span = null;
    var last_attr_value: ?Span = null;
    var open_tag_name: ?Span = null;

    while (true) {
        const token = tokenizer.next(src);
        // log("{s}: {s}", .{ @tagName(token.tag), token.span.slice(src) });
        switch (token.tag) {
            .eof, .invalid => break,
            .tag_name => {
                try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
                last_attr_name = null;
                last_attr_value = null;

                if (open_tag_name) |tag_span| {
                    if (isSelfClosingTag(tag_span.slice(src))) {
                        try res.append(.self_closing_tag);
                    }
                }

                // log("tag_name '{s}'", .{token.span.slice(src)});
                try res.append(.{ .static_tag_open = token.span });
                open_tag_name = token.span;
            },
            .tag_end_name => {
                try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
                last_attr_name = null;
                last_attr_value = null;

                if (open_tag_name) |tag_span| {
                    if (isSelfClosingTag(tag_span.slice(src))) {
                        try res.append(.self_closing_tag);
                    }
                }
                open_tag_name = null;
                try res.append(.static_tag_close);
            },
            .tag_self_close => {
                try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
                last_attr_name = null;
                last_attr_value = null;
                try res.append(.self_closing_tag);
                open_tag_name = null;
            },

            .text => {
                try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
                last_attr_name = null;
                last_attr_value = null;

                if (open_tag_name) |tag_span| {
                    if (isSelfClosingTag(tag_span.slice(src))) {
                        try res.append(.self_closing_tag);
                        open_tag_name = null;
                    }
                }

                var sn = token.span;
                while (mem.indexOfScalar(u8, sn.slice(src), '{')) |i| {
                    const p: Span = .{ .start = sn.start, .end = @intCast(sn.start + i) };
                    try res.append(.{ .static_text = p });
                    const end: u32 = @intCast(mem.indexOfScalarPos(u8, sn.slice(src), i, '}').?);
                    const spec: Span = .{ .start = sn.start + i + 1, .end = @intCast(sn.start + end) };
                    try res.append(.{ .dyn_text = spec });
                    sn.start = spec.end + 1;
                }
                if (sn.start != sn.end) try res.append(.{ .static_text = sn });
            },
            .attr_name => {
                try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
                last_attr_value = null;
                last_attr_name = token.span;
            },
            .attr_value => last_attr_value = token.span,

            .doctype,
            .comment,
            => {},
        }
    }
    try processPendingAttribute(&res, last_attr_name, last_attr_value, src);
    if (open_tag_name) |tag_span| {
        if (isSelfClosingTag(tag_span.slice(src))) {
            try res.append(.self_closing_tag);
        }
    }
    return .{ .src = src, .instructions = try res.toOwnedSlice() };
}
