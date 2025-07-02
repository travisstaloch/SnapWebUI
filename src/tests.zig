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
