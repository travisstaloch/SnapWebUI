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

/// SOA html document encoding with payloads each instruction type
/// Each array is indexed by the payload_index from InstructionId
pub const EncodedTemplate = struct {
    instructions: []InstructionId,
    /// String data storage
    strings: []u8,
    tag_opens: []StringRef,
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
    // If not null, this owns the memory for all slices.
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
        }
    }
};

/// Reference to a string in the strings buffer
pub const StringRef = packed struct {
    offset: u32,
    len: u32,

    pub fn slice(self: StringRef, strings: []const u8) []const u8 {
        return strings[self.offset .. self.offset + self.len];
    }
};

const ArrayLengths = struct {
    instructions_len: u32,
    strings_len: u32,
    tag_opens_len: u32,
    texts_len: u32,
    static_attrs_len: u32,
    dyn_texts_len: u32,
    static_dyn_attrs_len: u32,
    dyn_static_attrs_len: u32,
    dyn_dyn_attrs_len: u32,
    dyn_events_len: u32,
};

/// Calculate the total memory needed for all arrays with proper alignment
fn calculateTotalSize(lengths: ArrayLengths) struct { total: usize, offsets: [10]usize } {
    var total: usize = 0;
    var offsets: [10]usize = undefined;

    // Instructions
    offsets[0] = total;
    total += lengths.instructions_len * @sizeOf(InstructionId);
    total = std.mem.alignForward(usize, total, @alignOf(u8));

    // Strings (u8 array)
    offsets[1] = total;
    total += lengths.strings_len;
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    // Tag opens (StringRef array)
    offsets[2] = total;
    total += lengths.tag_opens_len * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    // Texts (StringRef array)
    offsets[3] = total;
    total += lengths.texts_len * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    // Static attrs ([2]StringRef array)
    offsets[4] = total;
    total += lengths.static_attrs_len * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf(StringRef));

    // Dyn texts (StringRef array)
    offsets[5] = total;
    total += lengths.dyn_texts_len * @sizeOf(StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    // Static dyn attrs ([2]StringRef array)
    offsets[6] = total;
    total += lengths.static_dyn_attrs_len * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    // Dyn static attrs ([2]StringRef array)
    offsets[7] = total;
    total += lengths.dyn_static_attrs_len * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    // Dyn dyn attrs ([2]StringRef array)
    offsets[8] = total;
    total += lengths.dyn_dyn_attrs_len * @sizeOf([2]StringRef);
    total = std.mem.alignForward(usize, total, @alignOf([2]StringRef));

    // Dyn events ([2]StringRef array)
    offsets[9] = total;
    total += lengths.dyn_events_len * @sizeOf([2]StringRef);

    return .{ .total = total, .offsets = offsets };
}

fn readArrayLengths(reader: anytype) !ArrayLengths {
    return ArrayLengths{
        .instructions_len = try reader.readInt(u32, .little),
        .strings_len = try reader.readInt(u32, .little),
        .tag_opens_len = try reader.readInt(u32, .little),
        .texts_len = try reader.readInt(u32, .little),
        .static_attrs_len = try reader.readInt(u32, .little),
        .dyn_texts_len = try reader.readInt(u32, .little),
        .static_dyn_attrs_len = try reader.readInt(u32, .little),
        .dyn_static_attrs_len = try reader.readInt(u32, .little),
        .dyn_dyn_attrs_len = try reader.readInt(u32, .little),
        .dyn_events_len = try reader.readInt(u32, .little),
    };
}

/// deserialization from single memory allocation
pub fn deserializeEncodedTemplate(allocator: Allocator, data: []const u8) !EncodedTemplate {
    var stream = std.io.fixedBufferStream(data);
    var reader = stream.reader();

    const lengths = try readArrayLengths(reader);
    const size_info = calculateTotalSize(lengths);

    const bytes = try allocator.alloc(u8, size_info.total);

    const instruction_bytes = bytes[size_info.offsets[0] .. size_info.offsets[0] + lengths.instructions_len * @sizeOf(InstructionId)];
    const instructions = std.mem.bytesAsSlice(InstructionId, instruction_bytes);

    const strings = bytes[size_info.offsets[1] .. size_info.offsets[1] + lengths.strings_len];

    const tag_opens_bytes = bytes[size_info.offsets[2] .. size_info.offsets[2] + lengths.tag_opens_len * @sizeOf(StringRef)];
    const tag_opens = std.mem.bytesAsSlice(StringRef, tag_opens_bytes);

    const texts_bytes = bytes[size_info.offsets[3] .. size_info.offsets[3] + lengths.texts_len * @sizeOf(StringRef)];
    const texts = std.mem.bytesAsSlice(StringRef, texts_bytes);

    const static_attrs_bytes = bytes[size_info.offsets[4] .. size_info.offsets[4] + lengths.static_attrs_len * @sizeOf([2]StringRef)];
    const static_attrs = std.mem.bytesAsSlice([2]StringRef, static_attrs_bytes);

    const dyn_texts_bytes = bytes[size_info.offsets[5] .. size_info.offsets[5] + lengths.dyn_texts_len * @sizeOf(StringRef)];
    const dyn_texts = std.mem.bytesAsSlice(StringRef, dyn_texts_bytes);

    const static_dyn_attrs_bytes = bytes[size_info.offsets[6] .. size_info.offsets[6] + lengths.static_dyn_attrs_len * @sizeOf([2]StringRef)];
    const static_dyn_attrs = std.mem.bytesAsSlice([2]StringRef, static_dyn_attrs_bytes);

    const dyn_static_attrs_bytes = bytes[size_info.offsets[7] .. size_info.offsets[7] + lengths.dyn_static_attrs_len * @sizeOf([2]StringRef)];
    const dyn_static_attrs = std.mem.bytesAsSlice([2]StringRef, dyn_static_attrs_bytes);

    const dyn_dyn_attrs_bytes = bytes[size_info.offsets[8] .. size_info.offsets[8] + lengths.dyn_dyn_attrs_len * @sizeOf([2]StringRef)];
    const dyn_dyn_attrs = std.mem.bytesAsSlice([2]StringRef, dyn_dyn_attrs_bytes);

    const dyn_events_bytes = bytes[size_info.offsets[9] .. size_info.offsets[9] + lengths.dyn_events_len * @sizeOf([2]StringRef)];
    const dyn_events = std.mem.bytesAsSlice([2]StringRef, dyn_events_bytes);

    // Read data directly into sub-slices
    for (instructions) |*instruction| instruction.* = try reader.readStruct(InstructionId);
    _ = try reader.readAll(strings);

    for (tag_opens) |*tag_open_ref| tag_open_ref.* = try reader.readStruct(StringRef);
    for (texts) |*text_ref| text_ref.* = try reader.readStruct(StringRef);

    for (static_attrs) |*pair| {
        pair[0] = try reader.readStruct(StringRef);
        pair[1] = try reader.readStruct(StringRef);
    }

    for (dyn_texts) |*text_ref| text_ref.* = try reader.readStruct(StringRef);

    for (static_dyn_attrs) |*pair| {
        pair[0] = try reader.readStruct(StringRef);
        pair[1] = try reader.readStruct(StringRef);
    }

    for (dyn_static_attrs) |*pair| {
        pair[0] = try reader.readStruct(StringRef);
        pair[1] = try reader.readStruct(StringRef);
    }

    for (dyn_dyn_attrs) |*pair| {
        pair[0] = try reader.readStruct(StringRef);
        pair[1] = try reader.readStruct(StringRef);
    }

    for (dyn_events) |*pair| {
        pair[0] = try reader.readStruct(StringRef);
        pair[1] = try reader.readStruct(StringRef);
    }

    return .{
        .instructions = @alignCast(instructions),
        .strings = strings,
        .tag_opens = @alignCast(tag_opens),
        .texts = @alignCast(texts),
        .static_attrs = @alignCast(static_attrs),
        .dyn_texts = @alignCast(dyn_texts),
        .static_dyn_attrs = @alignCast(static_dyn_attrs),
        .dyn_static_attrs = @alignCast(dyn_static_attrs),
        .dyn_dyn_attrs = @alignCast(dyn_dyn_attrs),
        .dyn_events = @alignCast(dyn_events),
        .bytes = bytes,
    };
}

pub fn freeEncodedTemplate(allocator: Allocator, template: EncodedTemplate) void {
    if (template.bytes) |bytes| allocator.free(bytes);
}
