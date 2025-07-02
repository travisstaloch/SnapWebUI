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

test "HtmlTokenizer template 1" {
    const HtmlTokenizer = @import("snap").HtmlTokenizer;
    const Expected = struct { HtmlTokenizer.Token.Tag, []const u8 };
    const check = struct {
        fn check(tz: *HtmlTokenizer, case: [:0]const u8, expected: Expected) !void {
            const token = tz.next(case);
            // std.debug.print("{s} {s}\n", .{ @tagName(token.tag), token.span.slice(case) });
            try testing.expectEqual(expected[0], token.tag);
            try testing.expectEqualStrings(expected[1], token.span.slice(case));
        }
    }.check;

    var tk = HtmlTokenizer{};
    const case =
        \\<div/>
        \\<div id=unquoted></div>
        \\<template id="app-template">
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
        \\      <input type="text" placeholder="Description..." id="new-todo" value="{input}" oninput="{eh__onNewTodoInput}" />
        \\      <button onclick="{eh__onAddTodoClick}">Add Todo</button>
        \\    </div>
        \\    <ul>{todos}</ul>
        \\  </div>
        \\</template>
    ;

    try check(&tk, case, .{ .tag_name, "div" });
    try check(&tk, case, .{ .tag_self_close, "/>" });

    try check(&tk, case, .{ .tag_name, "div" });
    try check(&tk, case, .{ .attr_name, "id" });
    try check(&tk, case, .{ .attr_value, "unquoted" });
    try check(&tk, case, .{ .tag_end_name, "div" });

    try check(&tk, case, .{ .tag_name, "template" });
    try check(&tk, case, .{ .attr_name, "id" });
    try check(&tk, case, .{ .attr_value, "app-template" });
    try check(&tk, case, .{ .text, "\n  " }); // FIXME insignificant ws
    try check(&tk, case, .{ .tag_name, "h1" });
    try check(&tk, case, .{ .text, "Snap Demo" });
    try check(&tk, case, .{ .tag_end_name, "h1" });
    try check(&tk, case, .{ .tag_name, "div" });
    try check(&tk, case, .{ .attr_name, "class" });
    try check(&tk, case, .{ .attr_value, "app" });
    try check(&tk, case, .{ .text, "\n    " }); // FIXME insignificant ws
    try check(&tk, case, .{ .tag_name, "h3" });
    try check(&tk, case, .{ .text, "Counter" });
    try check(&tk, case, .{ .tag_end_name, "h3" });
    try check(&tk, case, .{ .tag_name, "div" });
    try check(&tk, case, .{ .text, "\n      " }); // FIXME insignificant ws
    try check(&tk, case, .{ .tag_name, "button" });
    try check(&tk, case, .{ .attr_name, "style" });
    try check(&tk, case, .{ .attr_value, "margin: 0.25rem" });
    try check(&tk, case, .{ .attr_name, "onclick" });
    try check(&tk, case, .{ .attr_value, "{eh__onDecClick}" });
    try check(&tk, case, .{ .text, "-" });
    try check(&tk, case, .{ .tag_end_name, "button" });
    try check(&tk, case, .{ .tag_name, "button" });
    try check(&tk, case, .{ .attr_name, "style" });
    try check(&tk, case, .{ .attr_value, "margin: 0.25rem" });
    try check(&tk, case, .{ .attr_name, "onclick" });
    try check(&tk, case, .{ .attr_value, "{eh__onIncClick}" });
    try check(&tk, case, .{ .text, "+" });
    try check(&tk, case, .{ .tag_end_name, "button" });
    try check(&tk, case, .{ .tag_name, "span" });
    try check(&tk, case, .{ .text, "count {count}" });
    try check(&tk, case, .{ .tag_end_name, "span" });
    try check(&tk, case, .{ .tag_end_name, "div" });
    try check(&tk, case, .{ .tag_name, "h3" });
    try check(&tk, case, .{ .text, "Todos" });
    try check(&tk, case, .{ .tag_end_name, "h3" });
    try check(&tk, case, .{ .tag_name, "div" });
    try check(&tk, case, .{ .attr_name, "class" });
    try check(&tk, case, .{ .attr_value, "add-todo-section" });
    try check(&tk, case, .{ .text, "\n      " }); // FIXME insignificant ws
    try check(&tk, case, .{ .tag_name, "input" });
    try check(&tk, case, .{ .attr_name, "type" });
    try check(&tk, case, .{ .attr_value, "text" });
    try check(&tk, case, .{ .attr_name, "placeholder" });
    try check(&tk, case, .{ .attr_value, "Description..." });
    try check(&tk, case, .{ .attr_name, "id" });
    try check(&tk, case, .{ .attr_value, "new-todo" });
    try check(&tk, case, .{ .attr_name, "value" });
    try check(&tk, case, .{ .attr_value, "{input}" });
    try check(&tk, case, .{ .attr_name, "oninput" });
    try check(&tk, case, .{ .attr_value, "{eh__onNewTodoInput}" });
    try check(&tk, case, .{ .tag_self_close, "/>" });
    try check(&tk, case, .{ .tag_name, "button" });
    try check(&tk, case, .{ .attr_name, "onclick" });
    try check(&tk, case, .{ .attr_value, "{eh__onAddTodoClick}" });
    try check(&tk, case, .{ .text, "Add Todo" });
    try check(&tk, case, .{ .tag_end_name, "button" });
    try check(&tk, case, .{ .tag_end_name, "div" });
    try check(&tk, case, .{ .tag_name, "ul" });
    try check(&tk, case, .{ .text, "{todos}" });
    try check(&tk, case, .{ .tag_end_name, "ul" });
    try check(&tk, case, .{ .tag_end_name, "div" });
    try check(&tk, case, .{ .tag_end_name, "template" });
    try check(&tk, case, .{ .eof, "" });
}
