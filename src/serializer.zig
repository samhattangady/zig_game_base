// Some notes about deserialization
// Deserialization is currently type-neutral, so it treats all types as the same, which
// can cause an issue when some things are nested and others are not. Specifically when
// it comes to arraylists and hashmaps etc. There is an issue where we don't know exactly
// when they need to be initialised. So this is handled in the structs themselves. in its
// deserialization, a struct will init the things that it needs to, if it needs to. So
// things that are already initialised wont be affected, and things that need initializing
// will be taken care of.

const std = @import("std");
const c = @import("c.zig");
const build_options = @import("build_options");
const BUILDER_MODE = build_options.builder_mode;
const helpers = @import("helpers.zig");

const JSON_SERIALIZER_MAX_DEPTH = 32;
pub const JsonWriter = std.io.Writer(*JsonStream, JsonStreamError, JsonStream.write);
pub const JsonStreamError = error{JsonWriteError};
pub const JsonSerializer = std.json.WriteStream(JsonWriter, .{ .checked_to_fixed_depth = 256 });
pub const JsonStream = struct {
    const Self = @This();
    buffer: std.ArrayList(u8),

    pub fn new(allocator: std.mem.Allocator) Self {
        return Self{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn writer(self: *Self) JsonWriter {
        return .{ .context = self };
    }

    pub fn write(self: *Self, bytes: []const u8) JsonStreamError!usize {
        self.buffer.appendSlice(bytes) catch unreachable;
        return bytes.len;
    }

    // pub fn saveDataToFile(self: *Self, filepath: []const u8, allocator: std.mem.Allocator) !void {
    //     // TODO (08 Dec 2021 sam): See whether we want to add a hash or base64 encoding
    //     try helpers.writeFileContents(filepath, self.buffer.items, allocator);
    //     if (false) {
    //         helpers.debugPrint("saving to file {s}\n", .{filepath});
    //     }
    // }

    pub fn webSave(self: *Self, key_name: []const u8) !void {
        helpers.webSave(key_name, self.buffer.items);
    }

    pub fn debugPrint(self: *Self) void {
        helpers.debugPrint("{s}", .{self.buffer.items});
    }

    pub fn serializer(self: *Self) JsonSerializer {
        return std.json.writeStream(self.writer(), .{});
    }
};

pub fn serialize(opt_struct_name: ?[]const u8, data: anytype, js: *JsonSerializer) !void {
    // helpers.debugPrint("serializing {s} of type {s}\n", .{ opt_struct_name orelse "val", @typeName(@TypeOf(data)) });
    // @compileLog("", @typeName(@TypeOf(data)));
    switch (@typeInfo(@TypeOf(data))) {
        .Struct => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            if (comptime std.mem.indexOf(u8, @typeName(@TypeOf(data)), "array_list.ArrayListAligned") != null) {
                try js.beginArray();
                for (data.items) |val| {
                    try serialize(null, val, js);
                }
                try js.endArray();
            } else if (comptime std.mem.indexOf(u8, @typeName(@TypeOf(data)), "hash_map.HashMap") != null) {
                try js.beginArray();
                var items = data.keyIterator();
                while (items.next()) |key| {
                    try js.beginObject();
                    try serialize("key", key.*, js);
                    try serialize("value", data.get(key.*).?, js);
                    try js.endObject();
                }
                try js.endArray();
            } else {
                // TODO (28 Feb 2024 sam): Maybe we can move the ser/deser code here? Its anyways
                // common between almost all classes
                try js.beginObject();
                try serializeStruct(@TypeOf(data), data, js);
                try js.endObject();
            }
        },
        .Pointer => {
            helpers.assert(@TypeOf(data[0]) == u8); // Only supports strings
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.write(data);
        },
        .Optional => {
            if (data) |d| {
                try serialize(opt_struct_name, d, js);
            } else {
                if (opt_struct_name) |struct_name| try js.objectField(struct_name);
                try js.write(null);
            }
        },
        .Enum => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.write(@tagName(data));
        },
        .Float, .Int, .Bool => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.write(data);
        },
        .Union => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.beginObject();
            try serialize("case", @tagName(std.meta.activeTag(data)), js);
            switch (data) {
                inline else => |val| try serialize("value", val, js),
            }
            try js.endObject();
        },
        .Void, .Null => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.write("");
        },
        .Array => {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.beginArray();
            for (data[0..]) |elem| {
                try serialize(null, elem, js);
            }
            try js.endArray();
        },
        .Vector => |vector_data| {
            if (opt_struct_name) |struct_name| try js.objectField(struct_name);
            try js.beginArray();
            for (0..vector_data.len) |i| {
                try serialize(null, data[i], js);
            }
            try js.endArray();
        },
        else => comptime {
            var buffer: [512]u8 = undefined;
            const text = std.fmt.bufPrint(buffer[0..], "Could not serialize {s}\n", .{@tagName(@typeInfo(@TypeOf(data)))}) catch unreachable;
            @compileError(text);
        },
    }
}

pub fn serializeStruct(comptime T: type, data: T, js: *JsonSerializer) !void {
    helpers.assert(@typeInfo(T) == .Struct);
    if (@hasDecl(T, "serialize")) {
        helpers.debugPrint("{s} has a serialize()", .{@typeName(T)});
        try data.serialize(js);
    } else {
        if (@hasDecl(T, "serialize_fields")) {
            helpers.debugPrint("{s} has a list of serialize_fields", .{@typeName(T)});
            inline for (@field(T, "serialize_fields")) |field| try serialize(field, @field(data, field), js);
        } else {
            helpers.debugPrint("{s} - serializing all fields", .{@typeName(T)});
            inline for (@typeInfo(T).Struct.fields) |field| {
                try serialize(field.name, @field(data, field.name), js);
            }
        }
    }
}

// for desrializing. expects data to be a pointer to struct type
fn hasField(data: anytype, field: []const u8) bool {
    inline for (@typeInfo(@typeInfo(@TypeOf(data)).Pointer.child).Struct.fields) |f| {
        if (std.mem.eql(u8, f.name, field)) return true;
    }
    return false;
}

pub const DeserializationOptions = struct {
    error_on_not_found: bool = false,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
};

pub fn deserialize(opt_struct_name: ?[]const u8, data: anytype, js: std.json.Value, options: DeserializationOptions) void {
    //if (opt_struct_name) |str_name| helpers.debugPrint("deserializiing {s}\n", .{str_name});
    var not_found = false;
    const figured_type = @TypeOf(data.*);
    // var names = js.object.iterator();
    // while (names.next()) |name| helpers.debugPrint("found {s}\n", .{name.key_ptr.*});
    const value = get_field: {
        if (opt_struct_name) |struct_name| {
            if (js.object.get(struct_name)) |s| {
                break :get_field s;
            } else {
                helpers.debugPrint("{s} not found\n", .{struct_name});
                if (options.error_on_not_found) unreachable;
                not_found = true;
                break :get_field js;
            }
        } else {
            break :get_field js;
        }
    };
    if (not_found) {
        return;
    }
    if (comptime @typeInfo(figured_type) == .Optional) {
        if (value == .null) {
            data.* = null;
            return;
        } else {
            const new_type = @typeInfo(figured_type).Optional.child;
            data.* = undefined;
            deserializeType(&data.*.?, value, options, new_type);
            return;
        }
    }
    deserializeType(data, value, options, figured_type);
}

fn deserializeType(data: anytype, value: std.json.Value, options: DeserializationOptions, comptime T: type) void {
    const is_optional = @typeInfo(T) == .Optional;
    helpers.assert(!is_optional);
    switch (@typeInfo(T)) {
        .Struct => {
            if (comptime std.mem.indexOf(u8, @typeName(@TypeOf(data)), "array_list.ArrayListAligned") != null) {
                // TODO (26 Feb 2024 sam): Should this call deserialize on data.items and allow Array to take care of the rest?
                data.resize(value.array.items.len) catch unreachable;
                for (value.array.items, 0..) |item, i| {
                    deserialize(null, &data.items[i], item, options);
                }
            } else if (comptime std.mem.indexOf(u8, @typeName(@TypeOf(data)), "hash_map.HashMap") != null) {
                data.ensureTotalCapacity(@intCast(value.array.items.len)) catch unreachable;
                const kitype = @TypeOf(data.keyIterator().items);
                const keytype = @typeInfo(kitype).Pointer.child;
                const vitype = @TypeOf(data.valueIterator().items);
                const valtype = @typeInfo(vitype).Pointer.child;
                for (value.array.items) |item| {
                    var key: keytype = undefined;
                    var val: valtype = undefined;
                    deserialize("key", &key, item, options);
                    deserialize("value", &val, item, options);
                    data.put(key, val) catch unreachable;
                }
            } else {
                // TODO (28 Feb 2024 sam): Maybe we can move the ser/deser code here? Its anyways
                // common between almost all classes
                deserializeStruct(T, data, value, options);
            }
        },
        .Pointer => {
            data.* = value.string; // assumed that all pointers are strings
        },
        .Optional => {
            unreachable; // we should have taken care of optionals above
        },
        .Enum => {
            if (comptime is_optional) {
                data.*.? = std.meta.stringToEnum(@TypeOf(data.*.?), value.string).?;
            } else {
                data.* = std.meta.stringToEnum(T, value.string).?;
            }
        },
        .Float => |float_data| {
            // TODO (27 Feb 2024 sam): I think we can get the type directly, and no need to do this.
            if (float_data.bits == 16) data.* = @as(f16, @floatCast(value.float));
            if (float_data.bits == 32) data.* = @as(f32, @floatCast(value.float));
            if (float_data.bits == 64) data.* = @as(f64, @floatCast(value.float));
        },
        .Bool => {
            data.* = value.bool;
        },
        .Array => {
            for (value.array.items, 0..) |item, i| {
                deserialize(null, &data[i], item, options);
            }
        },
        .Vector => |vector_data| {
            for (0..vector_data.len) |i| {
                deserializeType(&data[i], value.array.items[i], options, vector_data.child);
            }
        },
        .Void => {
            data.* = {};
        },
        .Union => {
            const tag = @typeInfo(T).Union.tag_type.?;
            const case_name = value.object.get("case").?.string;
            const case = std.meta.stringToEnum(tag, case_name).?;
            switch (case) {
                inline else => |branch| {
                    const tag_name = @tagName(branch);
                    data.* = @unionInit(T, tag_name, undefined);
                    deserialize(null, &@field(data.*, tag_name), value.object.get("value").?, options);
                },
            }
        },
        .Int => |int_data| {
            // TODO (27 Feb 2024 sam): I think we can get the type directly, and no need to do this.
            switch (int_data.signedness) {
                .signed => {
                    if (int_data.bits == 4) data.* = @as(i4, @intCast(value.integer));
                    if (int_data.bits == 8) data.* = @as(i8, @intCast(value.integer));
                    if (int_data.bits == 16) data.* = @as(i16, @intCast(value.integer));
                    if (int_data.bits == 32) data.* = @as(i32, @intCast(value.integer));
                    if (int_data.bits == 64) data.* = @as(i64, @intCast(value.integer));
                },
                .unsigned => {
                    if (int_data.bits == 4) data.* = @as(u4, @intCast(value.integer));
                    if (int_data.bits == 8) data.* = @as(u8, @intCast(value.integer));
                    if (int_data.bits == 16) data.* = @as(u16, @intCast(value.integer));
                    if (int_data.bits == 32) data.* = @as(u32, @intCast(value.integer));
                    if (int_data.bits == 64) data.* = @as(u64, @intCast(value.integer));
                },
            }
        },
        else => {
            helpers.debugPrint("Could not deserialize {s}\n", .{@tagName(@typeInfo(T))});
        },
    }
}

pub fn deserializeStruct(comptime T: type, data: *T, value: std.json.Value, options: DeserializationOptions) void {
    helpers.assert(@typeInfo(T) == .Struct);
    // TODO (25 Jul 2024 sam): Create a struct with all the default values as they may be. It should not
    // overwrite things that are to be ignored (not in serializer_fields) etc. Maybe we just do this for
    // the standard all_fields case.
    {
        @setEvalBranchQuota(100000);
        const init_fields = [_][]const u8{ "array_list.ArrayListAligned", "hash_map.HashMap" };
        inline for (@typeInfo(T).Struct.fields) |field| {
            inline for (init_fields) |name| {
                if (comptime std.mem.indexOf(u8, @typeName(field.type), name) != null) {
                    @field(data.*, field.name) = @TypeOf(@field(data.*, field.name)).init(options.allocator);
                }
            }
        }
    }
    if (@hasDecl(T, "deserialize")) {
        data.deserialize(value, options);
        return;
    }
    if (@hasDecl(T, "serialize_fields")) {
        inline for (@field(T, "serialize_fields")) |field| deserialize(field, &@field(data, field), value, options);
    } else {
        inline for (@typeInfo(T).Struct.fields) |field| deserialize(field.name, &@field(data, field.name), value, options);
    }
}

pub fn allFieldNames(comptime T: type) [@typeInfo(T).Struct.fields.len][]const u8 {
    var buffer: [@typeInfo(T).Struct.fields.len][]const u8 = undefined;
    for (@typeInfo(T).Struct.fields, 0..) |field, i| buffer[i] = field.name;
    return buffer;
}

pub fn initFieldNames(comptime T: type) [@typeInfo(T).Struct.fields.len][]const u8 {
    @setEvalBranchQuota(100000);
    const init_fields = [_][]const u8{ "array_list.ArrayListAligned", "hash_map.HashMap" };
    var buffer: [@typeInfo(T).Struct.fields.len][]const u8 = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        buffer[i] = "";
        for (init_fields) |name| {
            if (comptime std.mem.indexOf(u8, @typeName(field.type), name) != null) {
                // var buf: [1000]u8 = undefined;
                // const text = std.fmt.bufPrint(buf[0..], "init field {s} in {s}", .{ field.name, @typeName(T) }) catch unreachable;
                // @compileLog(text);
                buffer[i] = field.name;
            }
        }
    }
    return buffer;
}
