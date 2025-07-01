const std = @import("std");
const testing = std.testing;
const lib = @import("snap");
const Node = lib.Node;
const h = lib.h;
const t = lib.t;

test "html formatting" {
    const node = h("div", &.{.a("class", "container")}, &.{}, &.{
        h("h1", &.{}, &.{}, &.{t("Hello World")}),
        h("p", &.{}, &.{}, &.{t("This is a <test> & example")}),
    });

    try std.testing.expectFmt(
        \\<div class="container"><h1>Hello World</h1><p>This is a &lt;test&gt; &amp; example</p></div>
    , "{html}", .{node});
}

test "Tokenizer template 1" {
    const Tokenizer = @import("snap").Tokenizer;
    const Expected = struct { Tokenizer.Token.Tag, []const u8 };
    const check = struct {
        fn check(tz: *Tokenizer, case: [:0]const u8, expected: Expected) !void {
            const token = tz.next(case);
            std.debug.print("{s} {s}\n", .{ @tagName(token.tag), token.span.slice(case) });
            try testing.expectEqual(expected[0], token.tag);
            try testing.expectEqualStrings(expected[1], token.span.slice(case));
        }
    }.check;

    var tk = Tokenizer{};
    const case =
        \\<template id="app-template"/>
        \\  <h1>Snap Demo</h1>
        \\  <div class="app">
        \\    <h3>Counter</h3>
        \\    <div>
        \\      <button style="margin: 0.25rem" onclick="{eh__onDecClick}">-</button>
        \\      <button style="margin: 0.25rem" onclick="{eh__onIncClick}">+</button>
        \\      <span>count {count}</span>
        \\    </div>
        \\    <h3>Todos</h3>
        \\    <div class="add-todo-section">
        \\      <input type=text placeholder="Description..." id="new-todo" value="{input}" oninput="{eh__onNewTodoInput}" />
        \\      <button onclick="{eh__onAddTodoClick}">Add Todo</button>
        \\    </div>
        \\    <ul>{todos}</ul>
        \\  </div>
        \\</template>
    ;

    try check(&tk, case, .{ .tag_name, "template" });
    try check(&tk, case, .{ .attr_name, "id" });
    try check(&tk, case, .{ .attr_value, "app-template" });
    try check(&tk, case, .{ .tag_self_close, "/>" });
    try check(&tk, case, .{ .tag_name, "h1" });
    try check(&tk, case, .{ .text, "Snap Demo" });
    try check(&tk, case, .{ .tag_end_name, "h1" });
    try check(&tk, case, .{ .tag_name, "div" });
}
