const std = @import("std");
const testing = std.testing;
const lib = @import("lib.zig");
const Node = lib.Node;
const h = lib.h;
const t = lib.t;
const diff = @import("diff.zig");
const Patch = diff.Patch;
// test {
//     _ = @import("diff.zig");
// }

test "basic diffing operations" {
    { // create new node
        const old_node = Node.empty;
        const new_node = t("hello");
        var patches = std.ArrayListUnmanaged(Patch){};
        defer patches.deinit(testing.allocator);
        try diff.diff(old_node, new_node, 0, &patches, testing.allocator);
        try testing.expectEqual(.create, std.meta.activeTag(patches.items[0]));
        try testing.expectEqualStrings(patches.items[0].create.text, "hello");
    }

    { // replace text node
        const old_node = t("hello");
        const new_node = t("world");
        var patches = std.ArrayListUnmanaged(Patch){};
        defer patches.deinit(testing.allocator);
        try diff.diff(old_node, new_node, 0, &patches, testing.allocator);
        try testing.expectEqual(.replace, std.meta.activeTag(patches.items[0]));
        try testing.expectEqualStrings(patches.items[0].replace.new_node.text, "world");
    }

    { // remove node
        const old_node = t("hello");
        const new_node = Node.empty;
        var patches = std.ArrayListUnmanaged(Patch){};
        defer patches.deinit(testing.allocator);
        try diff.diff(old_node, new_node, 0, &patches, testing.allocator);
        try testing.expectEqual(.remove, std.meta.activeTag(patches.items[0]));
    }

    { // update children
        const old_node = h("div", &.{}, &.{t("hello")}, &.{});
        const new_node = h("div", &.{}, &.{t("world")}, &.{});
        var patches = std.ArrayListUnmanaged(Patch){};
        defer patches.deinit(testing.allocator);
        try diff.diff(old_node, new_node, 0, &patches, testing.allocator);
        defer {
            for (patches.items) |*patch| {
                patch.deinit(testing.allocator);
            }
        }
        const expecteds = &[_]Patch{.{ .update = &.{.{ .replace = .{
            .old_node = t("hello"),
            .new_node = t("world"),
        } }} }};
        for (patches.items, expecteds) |actual, expected| {
            try testing.expect(expected.eql(actual));
        }
    }

    { // reorder nodes
        const old_node = h("div", &.{}, &.{ t("1"), t("2"), t("3") }, &.{});
        const new_node = h("div", &.{}, &.{ t("3"), t("2"), t("1") }, &.{});
        var patches = std.ArrayListUnmanaged(Patch){};
        defer {
            for (patches.items) |p| p.deinit(testing.allocator);
            patches.deinit(testing.allocator);
        }
        try diff.diff(old_node, new_node, 0, &patches, testing.allocator);
        try testing.expectEqual(.update, std.meta.activeTag(patches.items[0]));
    }
}

test "html formatting" {
    const node = h("div", &.{.a("class", "container")}, &.{
        h("h1", &.{}, &.{t("Hello World")}, &.{}),
        h("p", &.{}, &.{t("This is a <test> & example")}, &.{}),
    }, &.{});

    try std.testing.expectFmt(
        \\<div class="container"><h1>Hello World</h1><p>This is a &lt;test&gt; &amp; example</p></div>
    , "{html}", .{node});
}
