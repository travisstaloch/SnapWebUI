const std = @import("std");
const snap = @import("snap");
const NodeId = snap.NodeId;
const h = snap.h;
const t = snap.t;
const tf = snap.tf;
const hi = snap.hi;
const ti = snap.ti;

const App = struct {
    root_element: NodeId,
    count: i32 = 0,

    pub fn render(self: *App) !void {
        snap.js_begin_render(self.root_element);
        self.createView();
        snap.js_end_render();
    }

    fn createView(self: *App) void {
        var buf: [24]u8 = undefined;
        hi("div", &.{}, &.{}, &.{
            h("button", &.{.a("style", "margin: 0.5em;")}, &.{.e("click", &decrementCallback, self)}, &.{t("-")}),
            h("button", &.{.a("style", "margin: 0.5em;")}, &.{.e("click", &incrementCallback, self)}, &.{t("+")}),
            h("span", &.{.a("style", "")}, &.{}, &.{tf(&buf, "count {}", .{self.count})}),
        });
    }
};

fn incrementCallback(ctx: *anyopaque) !void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.count += 1;
    try app.render();
}

fn decrementCallback(ctx: *anyopaque) !void {
    const app: *App = @ptrCast(@alignCast(ctx));
    app.count -= 1;
    try app.render();
}

fn initInner() !void {
    const alloc = std.heap.wasm_allocator;
    const app = try alloc.create(App);
    app.* = .{
        .root_element = snap.querySelector("#app"),
        .count = 0,
    };
    try app.render();
}

export fn init() void {
    snap.logErr(initInner());
}
