const std = @import("std");
const testing = std.testing;
const snap = @import("snap");
const Node = snap.Node;
const h = snap.h;
const t = snap.t;

test "html formatting" {
    const node = h("div", &.{.a("class", "container")}, &.{}, &.{
        h("h1", &.{}, &.{}, &.{t("Hello World")}),
        h("p", &.{}, &.{}, &.{t("This is a <test> & example")}),
    });

    try std.testing.expectFmt(
        \\<div class="container"><h1>Hello World</h1><p>This is a &lt;test&gt; &amp; example</p></div>
    , "{html}", .{node});
}
