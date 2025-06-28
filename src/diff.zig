const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("lib.zig").Node;
const t = @import("lib.zig").t;
const h = @import("lib.zig").h;

pub const Patch = union(enum) {
    /// Create a new node
    create: Node,
    /// Update existing node properties
    update: []const Patch,
    /// Remove a node
    remove: usize,
    /// Replace entire node
    replace: struct {
        old_node: Node,
        new_node: Node,
    },
    /// Move node to new position
    reorder: struct {
        from_index: usize,
        to_index: usize,
    },

    pub fn deinit(self: Patch, allocator: std.mem.Allocator) void {
        if (self == .update) {
            for (self.update) |child_patch| {
                child_patch.deinit(allocator);
            }
            allocator.free(self.update);
        }
    }

    pub fn eql(self: Patch, other: Patch) bool {
        return std.meta.activeTag(self) == std.meta.activeTag(other) and switch (self) {
            .create => |s_create| s_create.eql(other.create),
            .update => |s_update| s_update.len == other.update.len and
                for (s_update, other.update) |s_child_patch, o_child_patch| {
                    if (!s_child_patch.eql(o_child_patch)) break false;
                } else true,
            .remove => |s_remove| s_remove == other.remove,
            .replace => |s_replace| s_replace.old_node.eql(other.replace.old_node) and
                s_replace.new_node.eql(other.replace.new_node),
            .reorder => |s_reorder| s_reorder.from_index == other.reorder.from_index and
                s_reorder.to_index == other.reorder.to_index,
        };
    }
};

pub fn diff(
    old_node: Node,
    new_node: Node,
    index: usize,
    patches: *std.ArrayListUnmanaged(Patch),
    allocator: Allocator,
) Allocator.Error!void {
    switch (old_node) {
        .empty => try patches.append(allocator, .{ .create = new_node }),
        .element => |old_el| {
            switch (new_node) {
                .empty => try patches.append(allocator, .{ .remove = index }),
                .element => |new_el| {
                    if (!std.mem.eql(u8, old_el.tag, new_el.tag)) {
                        try patches.append(allocator, .{ .replace = .{
                            .old_node = old_node,
                            .new_node = new_node,
                        } });
                        return;
                    }

                    var children_patches = try diffChildren(allocator, old_el.children, new_el.children);
                    defer children_patches.deinit(allocator);

                    if (children_patches.items.len > 0) {
                        try patches.append(allocator, .{ .update = try children_patches.toOwnedSlice(allocator) });
                    }
                },
                .text => try patches.append(allocator, .{ .replace = .{
                    .old_node = old_node,
                    .new_node = new_node,
                } }),
            }
        },
        .text => |old_text| {
            switch (new_node) {
                .text => |new_text| {
                    if (!std.mem.eql(u8, old_text, new_text)) {
                        try patches.append(allocator, .{ .replace = .{
                            .old_node = old_node,
                            .new_node = new_node,
                        } });
                    }
                },
                .empty => try patches.append(allocator, .{ .remove = index }),
                else => try patches.append(allocator, .{ .replace = .{
                    .old_node = old_node,
                    .new_node = new_node,
                } }),
            }
        },
    }
}

fn diffChildren(
    allocator: Allocator,
    old_children: []const Node,
    new_children: []const Node,
) !std.ArrayListUnmanaged(Patch) {
    var children_patches = std.ArrayListUnmanaged(Patch){};
    const min_len = @min(old_children.len, new_children.len);

    // Compare existing children
    for (0..min_len) |i| {
        try diff(old_children[i], new_children[i], i, &children_patches, allocator);
    }

    // Handle added children
    if (new_children.len > old_children.len) {
        for (min_len..new_children.len) |i| {
            try children_patches.append(allocator, .{ .create = new_children[i] });
        }
    }

    // Handle removed children
    if (old_children.len > new_children.len) {
        for (min_len..old_children.len) |i| {
            try children_patches.append(allocator, .{ .remove = i });
        }
    }
    return children_patches;
}
