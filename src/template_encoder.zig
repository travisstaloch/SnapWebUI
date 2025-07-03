const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const snap = @import("snap.zig");

/// Compact representation of render instruction tags
pub const InstructionTag = enum(u8) {
    static_tag_open = 0,
    static_tag_close = 1,
    static_text = 3,
    static_attribute = 4,
    dyn_text = 5,
    static_dyn_attr = 6,
    dyn_static_attr = 7,
    dyn_dyn_attr = 8,
    dyn_event = 9,
    dyn_attr_value_parts = 10,
};

/// Packed instruction ID that contains both tag and payload index
pub const InstructionId = packed struct(u32) {
    tag: InstructionTag,
    payload_index: u24,

    pub fn init(tag: InstructionTag, payload_index: u24) InstructionId {
        return .{ .tag = tag, .payload_index = payload_index };
    }
};

/// SOA html document encoding with payloads each instruction type
/// Each array is indexed by the payload_index from InstructionId
pub const EncodedTemplate = struct {
    instructions: []InstructionId,
    /// String data storage
    strings: []u8,
    /// marks the opening of a tag
    tag_opens: []StringRef,
    /// a text node
    texts: []StringRef,
    /// [name, value]
    static_attrs: [][2]StringRef,
    /// string offsets for field names
    dyn_texts: []StringRef,
    /// [static_name, dyn_field_name]
    static_dyn_attrs: [][2]StringRef,
    /// [dyn_field_name, static_value]
    dyn_static_attrs: [][2]StringRef,
    /// [dyn_field_name1, dyn_field_name2]
    dyn_dyn_attrs: [][2]StringRef,
    /// [event_name, handler_field_name]
    dyn_events: [][2]StringRef,
    /// (name, count, [type, ref]...)
    dyn_attr_value_parts: []u8,
    /// attribute value parts referenced by dyn_attr_value_parts
    dyn_attr_value_part_refs: []StringRef,
    // If not null, this is the memory for all slices.
    bytes: ?[]u8 = null,

    pub fn deinit(self: *EncodedTemplate, allocator: Allocator) void {
        if (self.bytes) |bytes| {
            allocator.free(bytes);
        } else {
            // For templates built with TemplateBuilder
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
            allocator.free(self.dyn_attr_value_parts);
            allocator.free(self.dyn_attr_value_part_refs);
        }
    }
};

/// Reference to a string in the strings buffer
pub const StringRef = extern struct {
    offset: u32,
    len: u32,

    pub fn slice(self: StringRef, strings: []const u8) []const u8 {
        return strings[self.offset .. self.offset + self.len];
    }
};

const ArrayLengths = struct {
    instructions: u32,
    strings: u32,
    tag_opens: u32,
    texts: u32,
    static_attrs: u32,
    dyn_texts: u32,
    static_dyn_attrs: u32,
    dyn_static_attrs: u32,
    dyn_dyn_attrs: u32,
    dyn_events: u32,
    dyn_attr_value_parts: u32,
    dyn_attr_value_part_refs: u32,
};

/// Calculate the total memory needed for all arrays with proper alignment
fn calculateTotalSize(lengths: ArrayLengths) struct { total: u32, offsets: ArrayLengths } {
    var total: u32 = 0;
    var offsets: ArrayLengths = undefined;

    offsets.instructions = total;
    total += lengths.instructions * @sizeOf(InstructionId);

    offsets.strings = total;
    total += lengths.strings;
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    offsets.tag_opens = total;
    total += lengths.tag_opens * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    offsets.texts = total;
    total += lengths.texts * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    offsets.static_attrs = total;
    total += lengths.static_attrs * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    offsets.dyn_texts = total;
    total += lengths.dyn_texts * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    offsets.static_dyn_attrs = total;
    total += lengths.static_dyn_attrs * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    offsets.dyn_static_attrs = total;
    total += lengths.dyn_static_attrs * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    offsets.dyn_dyn_attrs = total;
    total += lengths.dyn_dyn_attrs * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    offsets.dyn_events = total;
    total += lengths.dyn_events * @sizeOf([2]StringRef);
    // bytes. no align necessary

    offsets.dyn_attr_value_part_refs = total;
    total += lengths.dyn_attr_value_part_refs * @sizeOf(StringRef);
    // bytes. no align necessary

    offsets.dyn_attr_value_parts = total;
    total += lengths.dyn_attr_value_parts; // This is the raw byte length from JS

    return .{ .total = total, .offsets = offsets };
}

fn readArrayLengths(reader: anytype) !ArrayLengths {
    return ArrayLengths{
        .instructions = try reader.readInt(u32, .little),
        .strings = try reader.readInt(u32, .little),
        .tag_opens = try reader.readInt(u32, .little),
        .texts = try reader.readInt(u32, .little),
        .static_attrs = try reader.readInt(u32, .little),
        .dyn_texts = try reader.readInt(u32, .little),
        .static_dyn_attrs = try reader.readInt(u32, .little),
        .dyn_static_attrs = try reader.readInt(u32, .little),
        .dyn_dyn_attrs = try reader.readInt(u32, .little),
        .dyn_events = try reader.readInt(u32, .little),
        .dyn_attr_value_part_refs = try reader.readInt(u32, .little),
        .dyn_attr_value_parts = try reader.readInt(u32, .little),
    };
}

/// deserialize from js encoded bytes
pub fn deserializeEncodedTemplate(allocator: Allocator, data: []const u8) !EncodedTemplate {
    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();

    const lengths = try readArrayLengths(reader);

    // `data` is correctly aligned in js, so we can dupe and slice it up as is.
    const size_info = calculateTotalSize(lengths);
    if (data.len - stream.pos != size_info.total) {
        snap.panic("Malformed encoded template data: size mismatch.  (data.len - stream.pos):{} != size_info.total:{}", .{ data.len - stream.pos, size_info.total });
    }

    const bytes = try allocator.alloc(u8, size_info.total);
    const amt = try reader.read(bytes);
    if (amt != bytes.len) snap.panic("Read error.  Expected to read {} bytes but got {}.", .{ bytes.len, amt });

    return .{
        .instructions = @alignCast(mem.bytesAsSlice(InstructionId, bytes[size_info.offsets.instructions..size_info.offsets.strings])),
        .strings = bytes[size_info.offsets.strings..size_info.offsets.tag_opens],
        .tag_opens = @alignCast(mem.bytesAsSlice(StringRef, bytes[size_info.offsets.tag_opens..size_info.offsets.texts])),
        .texts = @alignCast(mem.bytesAsSlice(StringRef, bytes[size_info.offsets.texts..size_info.offsets.static_attrs])),
        .static_attrs = @alignCast(mem.bytesAsSlice([2]StringRef, bytes[size_info.offsets.static_attrs..size_info.offsets.dyn_texts])),
        .dyn_texts = @alignCast(mem.bytesAsSlice(StringRef, bytes[size_info.offsets.dyn_texts..size_info.offsets.static_dyn_attrs])),
        .static_dyn_attrs = @alignCast(mem.bytesAsSlice([2]StringRef, bytes[size_info.offsets.static_dyn_attrs..size_info.offsets.dyn_static_attrs])),
        .dyn_static_attrs = @alignCast(mem.bytesAsSlice([2]StringRef, bytes[size_info.offsets.dyn_static_attrs..size_info.offsets.dyn_dyn_attrs])),
        .dyn_dyn_attrs = @alignCast(mem.bytesAsSlice([2]StringRef, bytes[size_info.offsets.dyn_dyn_attrs..size_info.offsets.dyn_events])),
        .dyn_events = @alignCast(mem.bytesAsSlice([2]StringRef, bytes[size_info.offsets.dyn_events..size_info.offsets.dyn_attr_value_part_refs])),
        .dyn_attr_value_part_refs = @alignCast(mem.bytesAsSlice(StringRef, bytes[size_info.offsets.dyn_attr_value_part_refs..size_info.offsets.dyn_attr_value_parts])),
        .dyn_attr_value_parts = bytes[size_info.offsets.dyn_attr_value_parts..size_info.total],
        .bytes = bytes,
    };
}
