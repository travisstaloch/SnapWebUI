const std = @import("std");
const lib = @import("lib.zig");
const NodeId = lib.NodeId;
const Node = lib.Node;
const h = lib.h;
const t = lib.t;

fn createElementFromNode(node: Node) NodeId {
    switch (node) {
        .element => |vnode| {
            const el = createElement(vnode.tag);
            for (vnode.attributes) |attr| {
                js_set_attribute(el, attr.name.ptr, attr.name.len, attr.value.ptr, attr.value.len);
            }
            for (vnode.events) |event| {
                js_add_event_listener(el, event.name.ptr, event.name.len, @intFromPtr(event.callback), @intFromPtr(event.ctx));
            }
            for (vnode.children) |child| {
                const child_element = createElementFromNode(child);
                appendChild(el, child_element);
            }
            return el;
        },
        .text => |text| {
            return createTextElement(text);
        },
        .empty => {
            return createTextElement("");
        },
    }
}

/// Updates the DOM by comparing and reconciling differences between old and new virtual nodes
/// parent: The parent DOM node where changes will be applied
/// child_index: Index of the child node to update within the parent
/// new_node: The new virtual node state to render
/// old_node: The previous virtual node state to compare against
///
/// This function handles all node type transitions:
/// - empty → any: Creates and appends new element
/// - element → empty: Removes element
/// - element → element: Updates existing element and children recursively
/// - element → text: Replaces element with text
/// - text → any: Handles text node transitions
fn updateElement(parent: NodeId, child_index: usize, new_node: Node, old_node: Node) !void {
    // log("updateElement(parent: {} child_index: {}, new_node: {}, old_node: {})", .{ parent, child_index, new_node, old_node });
    switch (new_node) {
        .empty => {
            js_remove_child(parent, child_index);
        },
        .text => |new_text| {
            switch (old_node) {
                .text => |old_text| {
                    if (!std.mem.eql(u8, old_text, new_text)) {
                        const child = createElementFromNode(new_node);
                        js_replace_child(parent, child_index, child);
                    }
                },
                else => {
                    const child = createElementFromNode(new_node);
                    js_replace_child(parent, child_index, child);
                },
            }
        },
        .element => |new_vnode| {
            switch (old_node) {
                .empty => {
                    const child = createElementFromNode(new_node);
                    appendChild(parent, child);
                },
                .element => |old_vnode| {
                    if (!std.mem.eql(u8, old_vnode.tag, new_vnode.tag)) {
                        const child = createElementFromNode(new_node);
                        js_replace_child(parent, child_index, child);
                    } else {
                        const dom_node_to_update = js_get_child(parent, child_index);
                        // Diff attributes and set those changed
                        var old_attrs = std.StringHashMap([]const u8).init(std.heap.wasm_allocator);
                        defer old_attrs.deinit();
                        try old_attrs.ensureTotalCapacity(old_vnode.attributes.len);
                        for (old_vnode.attributes) |attr| {
                            try old_attrs.put(attr.name, attr.value);
                        }

                        for (new_vnode.attributes) |new_attr| {
                            if (old_attrs.get(new_attr.name)) |old_value| {
                                if (!std.mem.eql(u8, old_value, new_attr.value)) {
                                    js_set_attribute(dom_node_to_update, new_attr.name.ptr, new_attr.name.len, new_attr.value.ptr, new_attr.value.len);
                                }
                                _ = old_attrs.remove(new_attr.name);
                            } else {
                                js_set_attribute(dom_node_to_update, new_attr.name.ptr, new_attr.name.len, new_attr.value.ptr, new_attr.value.len);
                            }
                        }

                        // Remove old attributes
                        var old_attrs_it = old_attrs.iterator();
                        while (old_attrs_it.next()) |entry| {
                            js_set_attribute(dom_node_to_update, entry.key_ptr.*.ptr, entry.key_ptr.*.len, "".ptr, 0); // Set value to empty string to remove
                        }

                        // Diff children
                        var i: usize = 0;
                        while (i < new_vnode.children.len and i < old_vnode.children.len) : (i += 1) {
                            try updateElement(dom_node_to_update, i, new_vnode.children[i], old_vnode.children[i]);
                        }

                        // Add new children
                        while (i < new_vnode.children.len) : (i += 1) {
                            const child = createElementFromNode(new_vnode.children[i]);
                            appendChild(dom_node_to_update, child);
                        }

                        // Remove old children
                        while (i < old_vnode.children.len) : (i += 1) {
                            js_remove_child(dom_node_to_update, i);
                        }
                    }
                },
                .text => {
                    const child = createElementFromNode(new_node);
                    js_replace_child(parent, child_index, child);
                },
            }
        },
    }
}

// External JS functions
extern fn js_log(start: [*]const u8, len: usize) void;
extern fn js_query_selector(start: [*]const u8, len: usize) NodeId;
extern fn js_create_element(start: [*]const u8, len: usize) NodeId;
extern fn js_create_text_element(start: [*]const u8, len: usize) NodeId;
extern fn js_append_element(parent: NodeId, child: NodeId) void;
extern fn js_remove_child(parent: NodeId, child_index: usize) void;
extern fn js_replace_child(parent: NodeId, child_index: usize, child: NodeId) void;
extern fn js_get_child(parent: NodeId, child_index: usize) NodeId;
extern fn js_add_event_listener(element: NodeId, event_name_ptr: [*]const u8, event_name_len: usize, callback_ptr: usize, ctx_ptr: usize) void;
extern fn js_set_attribute(element: NodeId, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize) void;

pub export fn call_zig_callback(callback_ptr: usize, ctx_ptr: usize) void {
    const callback: *const lib.EventHandler.Callback = @ptrFromInt(callback_ptr);
    const ctx: *anyopaque = @ptrFromInt(ctx_ptr);
    logErr(callback(ctx));
}

// Helper functions
fn log(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    js_log(msg.ptr, msg.len);
}

fn EuPayload(eu: type) type {
    return switch (@typeInfo(eu)) {
        .error_union => |u| u.payload,
        else => unreachable,
    };
}

fn logErr(err: anytype) EuPayload(@TypeOf(err)) {
    return err catch |e| {
        log("error: {s}", .{@errorName(e)});
        return;
    };
}

fn querySelector(selector: []const u8) NodeId {
    return js_query_selector(selector.ptr, selector.len);
}

fn createElement(tag: []const u8) NodeId {
    return js_create_element(tag.ptr, tag.len);
}

fn createTextElement(text: []const u8) NodeId {
    return js_create_text_element(text.ptr, text.len);
}

fn appendChild(parent: NodeId, child: NodeId) void {
    js_append_element(parent, child);
}

const VDom = struct {
    node: Node,

    pub const empty: VDom = .{ .node = .empty };

    pub fn copyNode(self: *VDom, node: Node, allocator: std.mem.Allocator) !Node {
        return switch (node) {
            .empty => .empty,
            .text => |text| .{ .text = try allocator.dupe(u8, text) },
            .element => |vnode| {
                var children = try allocator.alloc(Node, vnode.children.len);
                for (vnode.children, 0..) |child, i| {
                    children[i] = try self.copyNode(child, allocator);
                }
                var events = try allocator.alloc(lib.EventHandler, vnode.events.len);
                for (vnode.events, 0..) |event, i| {
                    events[i] = .{ .name = try allocator.dupe(u8, event.name), .callback = event.callback, .ctx = event.ctx };
                }
                var attributes = try allocator.alloc(lib.Attribute, vnode.attributes.len);
                for (vnode.attributes, 0..) |attr, i| {
                    attributes[i] = .{ .name = try allocator.dupe(u8, attr.name), .value = try allocator.dupe(u8, attr.value) };
                }
                return .{ .element = .{ .tag = try allocator.dupe(u8, vnode.tag), .attributes = attributes, .children = children, .events = events } };
            },
        };
    }

    // pub fn freeNode(self: *VDom, node: Node, allocator: std.mem.Allocator) void {
    //     switch (node) {
    //         .empty => {},
    //         .text => |text| allocator.free(text),
    //         .element => |vnode| {
    //             allocator.free(vnode.tag);
    //             for (vnode.children) |child| {
    //                 self.freeNode(child, allocator);
    //             }
    //             allocator.free(vnode.children);
    //             for (vnode.events) |event| {
    //                 allocator.free(event.name);
    //             }
    //             allocator.free(vnode.events);
    //             for (vnode.attributes) |attr| {
    //                 allocator.free(attr.name);
    //                 allocator.free(attr.value);
    //             }
    //             allocator.free(vnode.attributes);
    //         },
    //     }
    // }

    const RenderCtx = struct {
        arena1: *std.heap.ArenaAllocator,
        arena2: *std.heap.ArenaAllocator,
    };

    pub fn render(self: *VDom, ctx: RenderCtx, el: NodeId, viewFn: anytype, viewArgs: anytype) !void {
        log("render() arena1.capacity: {} arena2.capacity {}", .{ ctx.arena1.queryCapacity(), ctx.arena2.queryCapacity() });
        const new_node = @call(.auto, viewFn, viewArgs);
        log("new_node {}\n", .{new_node});
        try updateElement(el, 0, new_node, self.node);
        // _ = ctx.arena.reset(.retain_capacity);
        self.node = try self.copyNode(new_node, ctx.arena1.allocator());
    }
};

fn counterView(current_count: i32, app: *App) Node {
    return h("div", &.{}, &.{
        h("span", &.{.{ .name = "style", .value = "padding-right: 1em;" }}, &.{
            t(std.fmt.allocPrint(app.arena1.allocator(), "count {d}", .{current_count}) catch "error"),
        }, &.{}),
        h("button", &.{}, &.{t("+")}, &.{
            .{
                .name = "click",
                .callback = struct {
                    fn func(ptr: *anyopaque) anyerror!void {
                        const this: *App = @ptrCast(@alignCast(ptr));
                        try this.count_state.set(this.count_state.inner + 1);
                    }
                }.func,
                .ctx = app,
            },
        }),
        h("button", &.{}, &.{t("-")}, &.{
            .{
                .name = "click",
                .callback = struct {
                    fn func(ptr: *anyopaque) anyerror!void {
                        const this: *App = @ptrCast(@alignCast(ptr));
                        try this.count_state.set(this.count_state.inner - 1);
                    }
                }.func,
                .ctx = app,
            },
        }),
    }, &.{
        // No attributes for the outer div
    });
}

const App = struct {
    node: NodeId,
    vd: VDom,
    count_state: lib.State(i32, *App),
    arena1: std.heap.ArenaAllocator,
    arena2: std.heap.ArenaAllocator,

    pub fn updateView(self: *App, current_count: i32) !void {
        try self.vd.render(
            .{ .arena1 = &self.arena1, .arena2 = &self.arena2 },
            self.node,
            counterView,
            .{ current_count, self },
        );
    }
};

comptime {
    if (@import("builtin").target.cpu.arch == .wasm32) @export(&init, .{ .name = "init" });
}

fn init() callconv(.c) void {
    logErr(initInner());
}

fn initInner() !void {
    const alloc = std.heap.wasm_allocator;
    const app = try alloc.create(App);
    app.* = .{
        .node = querySelector("#app"),
        .vd = .empty,
        .count_state = lib.useState(@as(i32, 0), app),
        .arena1 = std.heap.ArenaAllocator.init(std.heap.wasm_allocator),
        .arena2 = std.heap.ArenaAllocator.init(std.heap.wasm_allocator),
    };
    try app.updateView(app.count_state.inner);
}
