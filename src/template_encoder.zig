const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

/// Compact representation of render instruction tags
pub const InstructionTag = enum(u8) {
    static_tag_open = 0,
    static_tag_close = 1,
    self_closing_tag = 2,
    static_text = 3,
    static_attribute = 4,
    dyn_text = 5,
    static_dyn_attr = 6,
    dyn_static_attr = 7,
    dyn_dyn_attr = 8,
    dyn_event = 9,
};

/// Packed instruction ID that contains both tag and payload index
pub const InstructionId = packed struct(u32) {
    tag: InstructionTag,
    payload_index: u24,

    pub fn init(tag: InstructionTag, payload_index: u24) InstructionId {
        return .{ .tag = tag, .payload_index = payload_index };
    }
};

/// Structure-of-Arrays template representation
pub const EncodedTemplate = struct {
    /// Sequence of instruction IDs
    instructions: []InstructionId,

    /// String data storage
    strings: []u8,

    /// Payloads for different instruction types
    /// Each array is indexed by the payload_index from InstructionId
    /// For static_tag_open: string offsets into strings buffer
    tag_opens: []StringRef,

    /// For static_text: string offsets into strings buffer
    texts: []StringRef,

    /// For static_attribute: pairs of string offsets [name, value]
    static_attrs: [][2]StringRef,

    /// For dyn_text: string offsets for field names
    dyn_texts: []StringRef,

    /// For static_dyn_attr: [static_name, dyn_field_name]
    static_dyn_attrs: [][2]StringRef,

    /// For dyn_static_attr: [dyn_field_name, static_value]
    dyn_static_attrs: [][2]StringRef,

    /// For dyn_dyn_attr: [dyn_field_name1, dyn_field_name2]
    dyn_dyn_attrs: [][2]StringRef,

    /// For dyn_event: [event_name, handler_field_name]
    dyn_events: [][2]StringRef,

    pub fn deinit(self: *EncodedTemplate, allocator: Allocator) void {
        allocator.free(self.instructions);
        allocator.free(self.strings);
        allocator.free(self.tag_opens);
        allocator.free(self.texts);
        allocator.free(self.static_attrs);
        allocator.free(self.dyn_texts);
        allocator.free(self.static_dyn_attrs);
        allocator.free(self.dyn_static_attrs);
        allocator.free(self.dyn_dyn_attrs);
        allocator.free(self.dyn_events);
    }
};

/// Reference to a string in the strings buffer
pub const StringRef = struct {
    offset: u32,
    len: u32,

    pub fn slice(self: StringRef, strings: []const u8) []const u8 {
        return strings[self.offset .. self.offset + self.len];
    }
};

/// Builder for constructing EncodedTemplate
pub const TemplateBuilder = struct {
    allocator: Allocator,

    instructions: std.ArrayList(InstructionId),
    strings: std.ArrayList(u8),

    tag_opens: std.ArrayList(StringRef),
    texts: std.ArrayList(StringRef),
    static_attrs: std.ArrayList([2]StringRef),
    dyn_texts: std.ArrayList(StringRef),
    static_dyn_attrs: std.ArrayList([2]StringRef),
    dyn_static_attrs: std.ArrayList([2]StringRef),
    dyn_dyn_attrs: std.ArrayList([2]StringRef),
    dyn_events: std.ArrayList([2]StringRef),

    pub fn init(allocator: Allocator) TemplateBuilder {
        return .{
            .allocator = allocator,
            .instructions = std.ArrayList(InstructionId).init(allocator),
            .strings = std.ArrayList(u8).init(allocator),
            .tag_opens = std.ArrayList(StringRef).init(allocator),
            .texts = std.ArrayList(StringRef).init(allocator),
            .static_attrs = std.ArrayList([2]StringRef).init(allocator),
            .dyn_texts = std.ArrayList(StringRef).init(allocator),
            .static_dyn_attrs = std.ArrayList([2]StringRef).init(allocator),
            .dyn_static_attrs = std.ArrayList([2]StringRef).init(allocator),
            .dyn_dyn_attrs = std.ArrayList([2]StringRef).init(allocator),
            .dyn_events = std.ArrayList([2]StringRef).init(allocator),
        };
    }

    pub fn deinit(self: *TemplateBuilder) void {
        self.instructions.deinit();
        self.strings.deinit();
        self.tag_opens.deinit();
        self.texts.deinit();
        self.static_attrs.deinit();
        self.dyn_texts.deinit();
        self.static_dyn_attrs.deinit();
        self.dyn_static_attrs.deinit();
        self.dyn_dyn_attrs.deinit();
        self.dyn_events.deinit();
    }

    fn addString(self: *TemplateBuilder, str: []const u8) !StringRef {
        const offset: u32 = @intCast(self.strings.items.len);
        try self.strings.appendSlice(str);
        return StringRef{ .offset = offset, .len = @intCast(str.len) };
    }

    pub fn addStaticTagOpen(self: *TemplateBuilder, tag: []const u8) !void {
        const str_ref = try self.addString(tag);
        const payload_index: u24 = @intCast(self.tag_opens.items.len);
        try self.tag_opens.append(str_ref);
        try self.instructions.append(InstructionId.init(.static_tag_open, payload_index));
    }

    pub fn addStaticTagClose(self: *TemplateBuilder) !void {
        try self.instructions.append(InstructionId.init(.static_tag_close, 0));
    }

    pub fn addSelfClosingTag(self: *TemplateBuilder) !void {
        try self.instructions.append(InstructionId.init(.self_closing_tag, 0));
    }

    pub fn addStaticText(self: *TemplateBuilder, text: []const u8) !void {
        const str_ref = try self.addString(text);
        const payload_index: u24 = @intCast(self.texts.items.len);
        try self.texts.append(str_ref);
        try self.instructions.append(InstructionId.init(.static_text, payload_index));
    }

    pub fn addStaticAttribute(self: *TemplateBuilder, name: []const u8, value: []const u8) !void {
        const name_ref = try self.addString(name);
        const value_ref = try self.addString(value);
        const payload_index: u24 = @intCast(self.static_attrs.items.len);
        try self.static_attrs.append(.{ name_ref, value_ref });
        try self.instructions.append(InstructionId.init(.static_attribute, payload_index));
    }

    pub fn addDynText(self: *TemplateBuilder, field_name: []const u8) !void {
        const str_ref = try self.addString(field_name);
        const payload_index: u24 = @intCast(self.dyn_texts.items.len);
        try self.dyn_texts.append(str_ref);
        try self.instructions.append(InstructionId.init(.dyn_text, payload_index));
    }

    pub fn addStaticDynAttr(self: *TemplateBuilder, name: []const u8, field_name: []const u8) !void {
        const name_ref = try self.addString(name);
        const field_ref = try self.addString(field_name);
        const payload_index: u24 = @intCast(self.static_dyn_attrs.items.len);
        try self.static_dyn_attrs.append(.{ name_ref, field_ref });
        try self.instructions.append(InstructionId.init(.static_dyn_attr, payload_index));
    }

    pub fn addDynStaticAttr(self: *TemplateBuilder, field_name: []const u8, value: []const u8) !void {
        const field_ref = try self.addString(field_name);
        const value_ref = try self.addString(value);
        const payload_index: u24 = @intCast(self.dyn_static_attrs.items.len);
        try self.dyn_static_attrs.append(.{ field_ref, value_ref });
        try self.instructions.append(InstructionId.init(.dyn_static_attr, payload_index));
    }

    pub fn addDynDynAttr(self: *TemplateBuilder, name_field: []const u8, value_field: []const u8) !void {
        const name_ref = try self.addString(name_field);
        const value_ref = try self.addString(value_field);
        const payload_index: u24 = @intCast(self.dyn_dyn_attrs.items.len);
        try self.dyn_dyn_attrs.append(.{ name_ref, value_ref });
        try self.instructions.append(InstructionId.init(.dyn_dyn_attr, payload_index));
    }

    pub fn addDynEvent(self: *TemplateBuilder, event_name: []const u8, handler_field: []const u8) !void {
        const event_ref = try self.addString(event_name);
        const handler_ref = try self.addString(handler_field);
        const payload_index: u24 = @intCast(self.dyn_events.items.len);
        try self.dyn_events.append(.{ event_ref, handler_ref });
        try self.instructions.append(InstructionId.init(.dyn_event, payload_index));
    }

    pub fn build(self: *TemplateBuilder) !EncodedTemplate {
        return EncodedTemplate{
            .instructions = try self.instructions.toOwnedSlice(),
            .strings = try self.strings.toOwnedSlice(),
            .tag_opens = try self.tag_opens.toOwnedSlice(),
            .texts = try self.texts.toOwnedSlice(),
            .static_attrs = try self.static_attrs.toOwnedSlice(),
            .dyn_texts = try self.dyn_texts.toOwnedSlice(),
            .static_dyn_attrs = try self.static_dyn_attrs.toOwnedSlice(),
            .dyn_static_attrs = try self.dyn_static_attrs.toOwnedSlice(),
            .dyn_dyn_attrs = try self.dyn_dyn_attrs.toOwnedSlice(),
            .dyn_events = try self.dyn_events.toOwnedSlice(),
        };
    }
};
