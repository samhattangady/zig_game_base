const std = @import("std");
const c = @import("c.zig");

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sgapp = sokol.app_gfx_glue;
const sglue = sokol.glue;
const shd = @import("shaders/standard.zig");
const ztracy = @import("ztracy");
const serializer = @import("serializer.zig");

const VERTEX_BASE_FILE: [:0]const u8 = @embedFile("shaders/vertex.glsl");
const FRAGMENT_ALPHA_FILE: [:0]const u8 = @embedFile("shaders/fragment_texalpha.glsl");
const SPRITE_FRAGMENT_FILE: [:0]const u8 = @embedFile("shaders/fragments_tex.glsl");
const TEXTURE_SIZE = 512;

const helpers = @import("helpers.zig");
const Vec2i = helpers.Vec2i;
const Vec2 = helpers.Vec2;
const Vec3 = helpers.Vec3;
const Vec4 = helpers.Vec4;
const Rect = helpers.Rect;
const qoi = @import("qoi.zig");
const colors = @import("colors.zig");
const BG_COLOR = colors.palette0_1.lerp(colors.palette0_0, 0.4);
pub const USE_PALLETTE = true;
pub const TERRAIN_SIDE_FACE = false;

var circleX: f32 = 0;
var circleY: f32 = 0;
const MB_IN_BYTES = 1_048_576;

const FONT_PATH = "data/font_data.json";
const DEFAULT_RESOLUTION = 16.0 / 9.0;

const texMin = @as(f32, 1.0 / @as(comptime_float, TEXTURE_SIZE));
const circleTexCoords = [_]Vec2{
    .{ .x = texMin, .y = texMin },
    .{ .x = 1.0, .y = texMin },
    .{ .x = 1.0, .y = 1.0 },
    .{ .x = texMin, .y = 1.0 },
};

// The screen is always 1280x720 in resolution. If the window size is different, we will
// scale all things accordingly, and if the resolution changes, we draw black bars on the
// excess sections.
const WIDTH = 1280;
const HEIGHT = 720;
pub const SCREEN_SIZE = Vec2{ .x = WIDTH, .y = HEIGHT };

const ZLevel = enum {
    top,
    fg,
    bg,
};
const NUM_Z_LEVELS = @typeInfo(ZLevel).Enum.fields.len;

pub const VertexData = struct {
    position: Vec3 = .{},
    color: Vec4 = .{},
    tex_coord: Vec2 = .{},
};

const VertexBuffer = struct {
    const Self = @This();
    triangleVerts: std.ArrayList(VertexData),
    indices: std.ArrayList(c_uint),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .triangleVerts = std.ArrayList(VertexData).init(allocator),
            .indices = std.ArrayList(c_uint).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.triangleVerts.deinit();
        self.indices.deinit();
    }

    pub fn clearBuffers(self: *Self) void {
        self.triangleVerts.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }
};

pub const ShaderData = struct {
    program: c.GLuint = 0,
    texture: c.GLuint = 0,
};

pub const ShaderBuffer = struct {
    const Self = @This();
    buffers: [NUM_Z_LEVELS]VertexBuffer = undefined,

    pub fn init(allocator: std.mem.Allocator) Self {
        var self = Self{};
        for (0..NUM_Z_LEVELS) |i| {
            self.buffers[i] = VertexBuffer.init(allocator);
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (0..NUM_Z_LEVELS) |i| {
            self.buffers[i].deinit();
        }
    }

    pub fn clearBuffers(self: *Self) void {
        for (0..NUM_Z_LEVELS) |i| {
            self.buffers[i].clearBuffers();
        }
    }

    pub fn getBuffer(self: *Self, z_level: ZLevel) *VertexBuffer {
        return &self.buffers[@intFromEnum(z_level)];
    }

    pub fn getConstBuffer(self: *const Self, z_level: ZLevel) *const VertexBuffer {
        return &self.buffers[@intFromEnum(z_level)];
    }
};

fn sdlSetGlAttribute(attr: c.SDL_GLattr, value: c_int) void {
    const result = c.SDL_GL_SetAttribute(attr, value);
    if (result != 0) {
        helpers.debugPrint("error {d} in setting gl_attribute - {d}\n", .{ result, attr });
        c.SDL_Log("SDL_GL_SetAttribute Error: %s", c.SDL_GetError());
    }
}

pub const CharData = struct {
    tex0: Vec2,
    tex1: Vec2,
    size: Vec2i,
    offset: Vec2,
    xadvance: f32,
};

pub const ViewportData = struct {
    // window_size is the actual size of the window that is open
    window_size: Vec2i = .{ .x = WIDTH, .y = HEIGHT },
    /// user_window_size is the size of window before toggled to full_screen
    /// We store it so that when we toggle out of full screen, we know the size
    /// we were before that.
    user_window_size: Vec2i = .{ .x = WIDTH, .y = HEIGHT },
    /// viewport_size is the size of the viewport that we want to draw into.
    /// if the window is not 16:9 resolution, then this will be smalled
    viewport_size: Vec2i = .{ .x = WIDTH, .y = HEIGHT },
    /// For non standard resolution, we store the offsets of the viewport so that
    /// the rendering is done in the center of the window, with bars on sides or
    /// above and below as per the resolution of the window
    viewport_offsets: Vec2i = .{},
    viewport_zoom: f32 = 1,
    const serialize_fields = helpers.allFieldNames(@This());
    pub fn serialize(self: *const @This(), js: *serializer.JsonSerializer) !void {
        inline for (serialize_fields) |field| try serializer.serialize(field, @field(self, field), js);
    }
    pub fn deserialize(self: *@This(), js: std.json.Value, options: serializer.DeserializationOptions) void {
        inline for (serialize_fields) |field| serializer.deserialize(field, &@field(self, field), js, options);
    }
};

/// Frame is the frame of reference of the draw. Assume the world is an infinitely stretched
/// out flat 2d plane. Frame gives us the area covered with respect to what needs to be drawn.
/// The default has the origin at 0,0. So the corners are - x: 0, WIDTH and y: 0, HEIGHT
pub const Frame = struct {
    const Self = @This();
    origin: Vec2 = .{},
    zoom: f32 = 1,
    // TODO (26 Apr 2023 sam): Add window specs here or somewhere...
    const serialize_fields = helpers.allFieldNames(@This());
    pub fn serialize(self: *const @This(), js: *serializer.JsonSerializer) !void {
        inline for (serialize_fields) |field| try serializer.serialize(field, @field(self, field), js);
    }
    pub fn deserialize(self: *@This(), js: std.json.Value, options: serializer.DeserializationOptions) void {
        inline for (serialize_fields) |field| serializer.deserialize(field, &@field(self, field), js, options);
    }

    /// Convert a world position to a OpenGL screen position
    /// OpenGl considers the middle of the screen as 0, 0
    /// Leftmost point is x=-1, rightmost is x=1
    /// topmost point is y=1, bottommost is y=-1
    pub fn getCoords(self: *const Self, pos: Vec2, viewport: ViewportData) Vec3 {
        const zoom = self.zoom * viewport.viewport_zoom;
        const frame_width = @as(f32, @floatFromInt(viewport.viewport_size.x)) / zoom;
        const frame_height = @as(f32, @floatFromInt(viewport.viewport_size.y)) / zoom;
        const top = self.origin.y;
        const bottom = self.origin.y + frame_height;
        const left = self.origin.x;
        const right = self.origin.x + frame_width;
        const x = helpers.unlerp(left, right, pos.x);
        const y = helpers.unlerp(bottom, top, pos.y);
        return .{
            .x = (x - 0.5) * 2,
            .y = (y - 0.5) * 2,
        };
    }

    /// Convert a screen position (SDL) to world position
    /// SDL screen has origin at top left corner
    /// max x is window width
    /// max y is window height
    /// World position has origin at top left corner
    /// max x is fixed constant WIDTH - 1280
    /// max y is fixed constant HEIGHT - 720
    pub fn fromScreenPos(self: *const Self, pos: Vec2, viewport: ViewportData) Vec2 {
        const viewport_pos = pos.subtract(viewport.viewport_offsets.toVec2());
        const x_fract = viewport_pos.x / @as(f32, @floatFromInt(viewport.viewport_size.x));
        const y_fract = viewport_pos.y / @as(f32, @floatFromInt(viewport.viewport_size.y));
        const zoomed_width = WIDTH / self.zoom;
        const zoomed_height = HEIGHT / self.zoom;
        const left = self.origin.x;
        const right = self.origin.x + zoomed_width;
        const top = self.origin.y;
        const bottom = self.origin.y + zoomed_height;
        return .{
            .x = helpers.lerp(left, right, x_fract),
            .y = helpers.lerp(top, bottom, y_fract),
        };
    }

    /// Convert a world position to screen position (SDL)
    /// // TODO (24 May 2023 sam): Handle viewports stuffs.
    pub fn toScreenPos(self: *const Self, pos: Vec2) Vec2 {
        const width = WIDTH;
        const height = HEIGHT;
        const x = pos.x;
        const y = pos.y;
        const x_raw = (x - self.origin.x) * self.zoom;
        const y_raw = (y - self.origin.y) * self.zoom;
        const x_fract = 0.5 + (((x_raw) / (WIDTH / 2)) / 2);
        const y_fract = ((-y_raw / (HEIGHT / 2)) / 2) + 0.5;
        const screen_x = x_fract * width;
        const screen_y = y_fract * height;
        return .{ .x = screen_x, .y = screen_y };
    }

    pub fn getBounds(self: *const Self, viewport: ViewportData) Rect {
        var rect = Rect{ .position = self.origin, .size = undefined };
        const zoom = self.zoom * viewport.viewport_zoom;
        const frame_width = @as(f32, @floatFromInt(viewport.viewport_size.x)) / zoom;
        const frame_height = @as(f32, @floatFromInt(viewport.viewport_size.y)) / zoom;
        rect.size.x = frame_width;
        rect.size.y = frame_height;
        return rect;
    }

    pub fn getCenter(self: *const Self, viewport: ViewportData) Vec2 {
        const bounds = self.getBounds(viewport);
        return bounds.position.add(bounds.size.scale(0.5));
    }
};

const DrawCircleOptions = struct {
    position: Vec2,
    radius: f32,
    color: Vec4,
    z_level: ZLevel = .bg,
    frame: ?Frame = null,
};

const DrawTriangleOptions = struct {
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    color: Vec4,
    z_level: ZLevel = .bg,
    frame: ?Frame = null,
};

const DrawLineOptions = struct {
    p0: Vec2,
    p1: Vec2,
    width: f32 = 3,
    color: Vec4,
    z_level: ZLevel = .bg,
    frame: ?Frame = null,
};

const RectAnchor = enum {
    /// draw a rect with one corner at p0, and one at p1
    absolute,
    /// draw a rect at pos p0 of size p1,
    pos_size,
    /// draw a rect centered at p0, with size p1
    centered_size,
    /// rect is centered at y, and left margin at p0.x
    y_centered_left,
    /// p0 is the left top corner, p1 is the size.
    /// Negative size is not respected.
    left_top_relative,
};

const DrawRectOptions = struct {
    // p0 and p1 change meaning based on anchor. check RectAnchor.
    p0: Vec2,
    p1: Vec2,
    color: Vec4,
    z_level: ZLevel = .bg,
    frame: ?Frame = null,
    anchor: RectAnchor = .absolute,
};

const StringAnchor = enum {
    bottom_left,
    bottom_center,
};

const DrawTextOptions = struct {
    // TODO (12 May 2023 sam): Support unicode here?
    text: []const u8,
    position: Vec2,
    color: Vec4,
    anchor: StringAnchor = .bottom_center,
    z_level: ZLevel = .bg,
    // In cases where we want the text to remain same size even while zooming in and out.
    non_scaling: bool = false,
    frame: ?Frame = null,
    scale: f32 = 0.7,
};

const ShaderProgram = enum {
    base,
    text,
};
const NUM_SHADER_PROGRAMS = @typeInfo(ShaderProgram).Enum.fields.len;
const Pass = struct {
    vertex_buffer: sg.Buffer = .{},
    index_buffer: sg.Buffer = .{},
    pipeline: sg.Pipeline = .{},
    pass_action: sg.PassAction = .{},
    image: sg.Image = .{},
    sampler: sg.Sampler = .{},
    bindings: sg.Bindings = .{},
};

pub const Display = struct {
    const Self = @This();
    viewport: ViewportData,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    passes: [NUM_SHADER_PROGRAMS]Pass = undefined,
    vertex_buffer: sg.Buffer = .{},
    index_buffer: sg.Buffer = .{},
    terrain: Pass = .{},
    pipeline: sg.Pipeline = .{},
    pass_action: sg.PassAction = .{},
    image: sg.Image = .{},
    sampler: sg.Sampler = .{},
    text_atlas: sg.Image = .{},
    text_sampler: sg.Sampler = .{},
    bindings: sg.Bindings = .{},
    full_screen: bool = false,

    // TODO (12 May 2023 sam): move this all to a @@Typesetter file
    chars: std.AutoHashMap(u32, CharData),

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator, windowTitle: []const u8) !Self {
        _ = windowTitle;
        var self: Display = .{
            .viewport = undefined,
            .allocator = allocator,
            .arena = arena,
            .chars = std.AutoHashMap(u32, CharData).init(allocator),
        };
        self.initMainTexture();
        try self.initTextTexture();
        self.initTerrainTexture();
        self.initSokol();
        self.windowSizeUpdate(.{ .x = WIDTH, .y = HEIGHT });
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.chars.deinit();
    }

    fn initSokol(self: *Display) void {
        const scale = if (TERRAIN_SIDE_FACE) 2 else 1;
        self.terrain.vertex_buffer = sg.makeBuffer(.{ .type = .VERTEXBUFFER, .size = 18902772 * scale * (@sizeOf(VertexData)), .usage = .DYNAMIC });
        self.terrain.index_buffer = sg.makeBuffer(.{ .type = .INDEXBUFFER, .size = 5400792 * scale, .usage = .DYNAMIC });
        self.vertex_buffer = sg.makeBuffer(.{ .type = .VERTEXBUFFER, .size = 35 * MB_IN_BYTES, .usage = .DYNAMIC });
        self.index_buffer = sg.makeBuffer(.{ .type = .INDEXBUFFER, .size = 32 * MB_IN_BYTES, .usage = .DYNAMIC });
        const shader_desc = shd.shdShaderDesc(sg.queryBackend());
        const shader = sg.makeShader(shader_desc);
        var pipeline_desc = sg.PipelineDesc{
            .shader = shader,
        };
        pipeline_desc.layout.attrs[shd.ATTR_vs_position].format = .FLOAT3;
        pipeline_desc.layout.attrs[shd.ATTR_vs_in_color].format = .FLOAT4;
        pipeline_desc.layout.attrs[shd.ATTR_vs_in_texCoord].format = .FLOAT2;
        pipeline_desc.index_type = .UINT32;
        pipeline_desc.colors[0].blend = .{
            .enabled = true,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            .op_rgb = .DEFAULT,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .op_alpha = .DEFAULT,
        };
        self.pipeline = sg.makePipeline(pipeline_desc);
        const terrain_shader_desc = if (USE_PALLETTE) shd.terrainUsePalletteShaderDesc(sg.queryBackend()) else shd.terrainShaderDesc(sg.queryBackend());
        const terrain_shader = sg.makeShader(terrain_shader_desc);
        pipeline_desc.shader = terrain_shader;
        self.terrain.pipeline = sg.makePipeline(pipeline_desc);
        self.pass_action.colors[0] = .{
            // clearColor
            .load_action = .CLEAR,
            .clear_value = .{ .r = BG_COLOR.x, .g = BG_COLOR.y, .b = BG_COLOR.z, .a = 1 },
        };
        self.bindings.vertex_buffers[0] = self.vertex_buffer;
        self.bindings.index_buffer = self.index_buffer;
        self.bindings.fs.images[shd.SLOT_tex] = self.image;
        self.bindings.fs.samplers[shd.SLOT_smp] = self.sampler;
        self.terrain.bindings.vertex_buffers[0] = self.terrain.vertex_buffer;
        self.terrain.bindings.index_buffer = self.terrain.index_buffer;
        self.terrain.bindings.fs.images[shd.SLOT_tex] = self.terrain.image;
        self.terrain.bindings.fs.samplers[shd.SLOT_smp] = self.terrain.sampler;
    }

    fn initGl(self: *Self) !void {
        c.glGenVertexArrays(1, &self.vao);
        c.glGenBuffers(1, &self.vbo);
        c.glGenBuffers(1, &self.ebo);
        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        // TODO (13 Jun 2021 sam): Figure out where this gets saved. Currently both the vertex types have
        // the same attrib pointers, so it's okay for now, but once we have more programs, we would need
        // to see where this gets saved, and whether we need more vaos or vbos or whatever.
        c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(VertexData), @as(*allowzero const anyopaque, @ptrFromInt(@offsetOf(VertexData, "position"))));
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(1, 4, c.GL_FLOAT, c.GL_FALSE, @sizeOf(VertexData), @as(*const anyopaque, @ptrFromInt(@offsetOf(VertexData, "color"))));
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(VertexData), @as(*const anyopaque, @ptrFromInt(@offsetOf(VertexData, "tex_coord"))));
        c.glEnableVertexAttribArray(2);
        try self.initShaderProgram(VERTEX_BASE_FILE, FRAGMENT_ALPHA_FILE, &self.shaders[@intFromEnum(ShaderProgram.base)]);
        try self.initShaderProgram(VERTEX_BASE_FILE, FRAGMENT_ALPHA_FILE, &self.shaders[@intFromEnum(ShaderProgram.text)]);
    }

    /// This currently only generates a circle texture that we can use to draw filled circles.
    fn initMainTexture(self: *Self) void {
        const temp_bitmap = self.allocator.alloc(u8, TEXTURE_SIZE * TEXTURE_SIZE) catch unreachable;
        defer self.allocator.free(temp_bitmap);
        // First we initialise the temp_bitmap to 0.
        // Is this necessary? We anyway explicity set the pixel values of all pixels we use.
        @memset(temp_bitmap, 0);
        // The circle texture leaves one pixel at 0,0 as filled, so all other fills can use that
        temp_bitmap[0] = 255;
        const radius: usize = (TEXTURE_SIZE - 1) / 2;
        const center = Vec2.fromInts(radius, radius);
        for (1..TEXTURE_SIZE) |i| {
            for (1..TEXTURE_SIZE) |j| {
                const current = Vec2.fromInts(i - 1, j - 1);
                if (center.distance(current) <= @as(f32, @floatFromInt(radius))) {
                    temp_bitmap[(i * TEXTURE_SIZE) + j] = 255;
                } else {
                    temp_bitmap[(i * TEXTURE_SIZE) + j] = 0;
                }
            }
        }
        var image_desc = sg.ImageDesc{
            .width = TEXTURE_SIZE,
            .height = TEXTURE_SIZE,
            .pixel_format = .R8,
        };
        image_desc.data.subimage[0][0] = .{ .size = TEXTURE_SIZE * TEXTURE_SIZE, .ptr = temp_bitmap.ptr };
        self.image = sg.makeImage(image_desc);
        self.sampler = sg.makeSampler(.{});
    }

    /// Loads texture from file.
    fn initTextTexture(self: *Self) !void {
        const file_data = try helpers.readFileContents(FONT_PATH, self.arena);
        // TODO (12 May 2023 sam): This all should go to @@Typesetter
        const tree = try std.json.parseFromSlice(std.json.Value, self.arena, file_data, .{});
        var js = tree.value;
        var chars_data = js.object.get("glyphs").?;
        var chars = chars_data.object.iterator();
        while (chars.next()) |char| {
            const dict = char.value_ptr.*;
            const code = std.fmt.parseInt(u32, char.key_ptr.*, 10) catch unreachable;
            const size = Vec2i{
                .x = @as(i32, @intCast(dict.object.get("w").?.integer)),
                .y = @as(i32, @intCast(dict.object.get("h").?.integer)),
            };
            const tex0 = Vec2{
                .x = @as(f32, @floatCast(dict.object.get("x0").?.float)),
                .y = @as(f32, @floatCast(dict.object.get("y0").?.float)),
            };
            const data = CharData{
                .tex0 = tex0,
                // This 512 needs to comer from @@Typesetter
                .tex1 = tex0.add(size.toVec2().scale(1.0 / 512.0)),
                .size = size,
                .offset = .{
                    .x = @as(f32, @floatFromInt(dict.object.get("xoff").?.integer)),
                    .y = @as(f32, @floatFromInt(dict.object.get("yoff").?.integer)),
                },
                .xadvance = @as(f32, @floatCast(dict.object.get("xadvance").?.float)),
            };
            self.chars.put(code, data) catch unreachable;
        }
        const font_tex_width: i32 = @as(i32, @intCast(js.object.get("texture_data").?.object.get("width").?.integer));
        const font_tex_height: i32 = @as(i32, @intCast(js.object.get("texture_data").?.object.get("height").?.integer));
        var encoded_comp_font_texture = std.ArrayList(u8).init(self.arena);
        encoded_comp_font_texture.appendSlice(js.object.get("texture_data").?.object.get("data").?.string) catch unreachable;
        // decode base64
        var decoder = std.base64.standard.Decoder;
        const comp_font_texture = self.arena.alloc(u8, decoder.calcSizeUpperBound(encoded_comp_font_texture.items.len) catch unreachable) catch unreachable;
        decoder.decode(comp_font_texture, encoded_comp_font_texture.items) catch unreachable;
        //uncompress the texture
        var fib = std.io.fixedBufferStream(comp_font_texture);
        const reader = fib.reader();

        var decompression = std.compress.flate.decompressor(reader);
        const decompressed = try decompression.reader().readAllAlloc(self.arena, std.math.maxInt(usize));

        var image_desc = sg.ImageDesc{
            .width = font_tex_width,
            .height = font_tex_height,
            .pixel_format = .R8,
        };
        image_desc.data.subimage[0][0] = .{ .size = @intCast(font_tex_width * font_tex_height), .ptr = decompressed.ptr };
        self.text_atlas = sg.makeImage(image_desc);
        self.text_sampler = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
    }

    fn initTerrainTexture(self: *Self) void {
        if (USE_PALLETTE) {
            self.terrain.image = self.image;
        } else {
            const t0 = std.time.milliTimestamp();
            helpers.debugPrint("start terrain readFileContents\n", .{});
            const file_data = helpers.readFileContents("data/images/paint_tiles_atlas.qoi", self.arena) catch unreachable;
            const t1 = std.time.milliTimestamp();
            helpers.debugPrint("terrain readFileContents in {d} ms\n", .{t1 - t0});
            const image = qoi.decodeBuffer(self.arena, file_data) catch unreachable;
            const t2 = std.time.milliTimestamp();
            helpers.debugPrint("terrain decodeBufferQoi in {d} ms\n", .{t2 - t1});
            var image_desc = sg.ImageDesc{
                .width = @intCast(image.width),
                .height = @intCast(image.height),
                .pixel_format = .RGBA8,
            };
            image_desc.data.subimage[0][0] = .{ .size = @intCast(image.width * image.height * 4), .ptr = image.pixels.ptr };
            self.terrain.image = sg.makeImage(image_desc);
            const t3 = std.time.milliTimestamp();
            helpers.debugPrint("terrain makeImage in {d} ms\n", .{t3 - t2});
        }
        self.terrain.sampler = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
    }

    fn initShaderProgram(self: *Self, vertex_src: []const u8, fragment_src: []const u8, shader_prog: *ShaderData) !void {
        _ = self;
        const fs: ?[*]const u8 = fragment_src.ptr;
        const fragment_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        {
            c.glShaderSource(fragment_shader, 1, &fs, null);
            c.glCompileShader(fragment_shader);
            var compile_success: c_int = undefined;
            c.glGetShaderiv(fragment_shader, c.GL_COMPILE_STATUS, &compile_success);
            if (compile_success == 0) {
                helpers.debugPrint("Fragment shader compilation failed\n", .{});
                var compileMessage: [1024]u8 = undefined;
                c.glGetShaderInfoLog(fragment_shader, 1024, null, &compileMessage[0]);
                helpers.debugPrint("{s}\n", .{compileMessage});
                return error.FragmentSyntaxError;
            }
        }
        var vs: ?[*]const u8 = vertex_src.ptr;
        const vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
        {
            c.glShaderSource(vertex_shader, 1, &vs, null);
            c.glCompileShader(vertex_shader);
            var compile_success: c_int = undefined;
            c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &compile_success);
            if (compile_success == 0) {
                helpers.debugPrint("Vertex shader compilation failed\n", .{});
                var compileMessage: [1024]u8 = undefined;
                c.glGetShaderInfoLog(vertex_shader, 1024, null, &compileMessage[0]);
                helpers.debugPrint("{s}\n", .{compileMessage});
                return error.VertexSyntaxError;
            }
        }
        shader_prog.program = c.glCreateProgram();
        c.glAttachShader(shader_prog.program, vertex_shader);
        c.glAttachShader(shader_prog.program, fragment_shader);
        c.glLinkProgram(shader_prog.program);
        c.glDeleteShader(vertex_shader);
        c.glDeleteShader(fragment_shader);
    }

    pub fn windowSizeUpdate(self: *Self, size: Vec2i) void {
        self.viewport.window_size = size;
        const resolution = @as(f32, @floatFromInt(size.x)) / @as(f32, @floatFromInt(size.y));
        if (resolution == DEFAULT_RESOLUTION) {
            self.viewport.viewport_size = size;
            self.viewport.viewport_offsets = .{};
        } else if (resolution > DEFAULT_RESOLUTION) {
            // x is dominant, so we need side bars.
            self.viewport.viewport_size.x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(size.y)) * DEFAULT_RESOLUTION));
            self.viewport.viewport_size.y = size.y;
            self.viewport.viewport_offsets.x = @divFloor(size.x - self.viewport.viewport_size.x, 2);
            self.viewport.viewport_offsets.y = 0;
        } else {
            // y is dominant, so we need top and bottom bars.
            self.viewport.viewport_size.x = size.x;
            self.viewport.viewport_size.y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(size.x)) / DEFAULT_RESOLUTION));
            self.viewport.viewport_offsets.x = 0;
            self.viewport.viewport_offsets.y = @divFloor(size.y - self.viewport.viewport_size.y, 2);
        }
        self.viewport.viewport_zoom = @as(f32, @floatFromInt(self.viewport.viewport_size.x)) / 1280.0;
    }

    pub fn toggleFullScreen(self: *Self) void {
        if (!self.full_screen) self.viewport.user_window_size = self.viewport.window_size;
        self.full_screen = !self.full_screen;
        sapp.toggleFullscreen();
        if (self.full_screen) {
            self.windowSizeUpdate(.{ .x = sapp.width(), .y = sapp.height() });
        } else {
            self.windowSizeUpdate(self.viewport.user_window_size);
        }
    }

    pub fn displayRenderer(self: *Self, ticks: u64, renderer: Renderer) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        _ = ticks;
        {
            const tracy_zone_section = ztracy.ZoneN(@src(), "sokol_setup");
            defer tracy_zone_section.End();
            if (self.full_screen != renderer.full_screen) self.toggleFullScreen();
            if (renderer.update_window) |size| {
                self.windowSizeUpdate(size);
            }
            sg.beginPass(.{
                .action = self.pass_action,
                .swapchain = sglue.swapchain(),
            });
            sg.applyViewport(self.viewport.viewport_offsets.x, self.viewport.viewport_offsets.y, self.viewport.viewport_size.x, self.viewport.viewport_size.y, true);
        }
        { // terrain
            const tracy_zone_section = ztracy.ZoneN(@src(), "terrain draw");
            defer tracy_zone_section.End();
            const tracy_zone_section0 = ztracy.ZoneN(@src(), "terrain draw0");
            if (renderer.terrain_update) {
                const vertex_range = sg.Range{ .size = renderer.terrain_buffer.triangleVerts.items.len * @sizeOf(VertexData), .ptr = renderer.terrain_buffer.triangleVerts.items.ptr };
                sg.updateBuffer(self.terrain.vertex_buffer, vertex_range);
                const index_range = sg.Range{ .size = renderer.terrain_buffer.indices.items.len * @sizeOf(c_uint), .ptr = renderer.terrain_buffer.indices.items.ptr };
                sg.updateBuffer(self.terrain.index_buffer, index_range);
            }
            const frame_uniform = FrameUniform{
                .frame_origin = renderer.frame.origin.toExtern(),
                .viewport_size = self.viewport.viewport_size.toVec2().toExtern(),
                .viewport_zoom = self.viewport.viewport_zoom,
                .frame_zoom = renderer.frame.zoom,
            };
            tracy_zone_section0.End();
            const tracy_zone_section1 = ztracy.ZoneN(@src(), "terrain draw1");
            self.terrain.bindings.vertex_buffer_offsets[0] = 0;
            self.terrain.bindings.index_buffer_offset = 0;
            tracy_zone_section1.End();
            const tracy_zone_section2 = ztracy.ZoneN(@src(), "terrain draw2");
            sg.applyPipeline(self.terrain.pipeline);
            tracy_zone_section2.End();
            const tracy_zone_section3 = ztracy.ZoneN(@src(), "terrain draw3");
            sg.applyBindings(self.terrain.bindings);
            tracy_zone_section3.End();
            const tracy_zone_section4 = ztracy.ZoneN(@src(), "terrain draw4");
            sg.applyUniforms(.VS, shd.SLOT_Frame, sg.Range{ .size = 32, .ptr = &frame_uniform });
            tracy_zone_section4.End();
            const tracy_zone_section5 = ztracy.ZoneN(@src(), "terrain draw5");
            sg.draw(0, @intCast(renderer.terrain_buffer.indices.items.len), 1);
            tracy_zone_section5.End();
        }
        self.bindings.vertex_buffer_offsets[0] = 0;
        self.bindings.index_buffer_offset = 0;
        {
            const tracy_zone_section = ztracy.ZoneN(@src(), "other draw");
            defer tracy_zone_section.End();
            for (0..NUM_Z_LEVELS) |z| {
                const z_level: ZLevel = @enumFromInt(NUM_Z_LEVELS - (z + 1));
                // for buffer.
                for (renderer.buffers, 0..) |buffer, i| {
                    const buf_type: ShaderProgram = @enumFromInt(i);
                    const buf = buffer.getConstBuffer(z_level);
                    if (buf.triangleVerts.items.len == 0) continue;
                    const vertex_range = sg.Range{ .size = buf.triangleVerts.items.len * @sizeOf(VertexData), .ptr = buf.triangleVerts.items.ptr };
                    const vertex_offset = sg.appendBuffer(self.vertex_buffer, vertex_range);
                    const index_range = sg.Range{ .size = buf.indices.items.len * @sizeOf(c_uint), .ptr = buf.indices.items.ptr };
                    const index_offset = sg.appendBuffer(self.index_buffer, index_range);
                    self.bindings.vertex_buffer_offsets[0] = vertex_offset;
                    self.bindings.index_buffer_offset = index_offset;
                    self.bindings.fs.images[shd.SLOT_tex] = switch (buf_type) {
                        .base => self.image,
                        .text => self.text_atlas,
                    };
                    sg.applyPipeline(self.pipeline);
                    sg.applyBindings(self.bindings);
                    sg.draw(0, @intCast(buf.indices.items.len), 1);
                }
            }
        }
        const tracy_zone_end_pass = ztracy.ZoneN(@src(), "SokolEndPass");
        sg.endPass();
        tracy_zone_end_pass.End();
        const tracy_zone_commit = ztracy.ZoneN(@src(), "SokolCommit");
        defer tracy_zone_commit.End();
        sg.commit();
    }
};

pub const FrameUniform = extern struct {
    frame_origin: helpers.Vec2Extern,
    viewport_size: helpers.Vec2Extern,
    viewport_zoom: f32,
    frame_zoom: f32,
};

pub const Renderer = struct {
    const Self = @This();
    frame: Frame = .{},
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    viewport: ViewportData = undefined,
    /// Flag for display to update
    update_window: ?Vec2i = null,
    buffers: [NUM_SHADER_PROGRAMS]ShaderBuffer = undefined,
    terrain_buffer: VertexBuffer = undefined,
    full_screen: bool = false,
    terrain_update: bool = true,
    chars: *std.AutoHashMap(u32, CharData) = undefined,

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator, viewport: ViewportData) Self {
        var self = Self{
            .allocator = allocator,
            .arena = arena,
            .viewport = viewport,
        };
        self.initBuffers();
        self.terrain_buffer = VertexBuffer.init(self.allocator);
        return self;
    }

    pub fn initBuffers(self: *Self) void {
        self.update_window = null;
        for (&self.buffers) |*buffer| buffer.* = ShaderBuffer.init(self.allocator);
    }

    pub fn clearBuffers(self: *Self) void {
        for (&self.buffers) |*buffer| buffer.clearBuffers();
    }

    pub fn deinit(self: *Self) void {
        for (&self.buffers) |*buffer| buffer.deinit();
        self.terrain_buffer.deinit();
    }

    pub fn setFrame(self: *Self, frame: Frame) void {
        self.frame = frame;
    }

    pub fn windowSizeUpdate(self: *Self, size: Vec2i) void {
        self.update_window = size;
    }

    pub fn toggleFullScreen(self: *Self) void {
        self.full_screen = !self.full_screen;
    }

    pub fn drawCircle(self: *Self, circle: DrawCircleOptions) void {
        const frame = circle.frame orelse self.frame;
        const center = circle.position;
        const radius = circle.radius;
        const pos0 = center.add(.{ .x = -radius, .y = -radius });
        const pos1 = center.add(.{ .x = -radius, .y = radius });
        const pos2 = center.add(.{ .x = radius, .y = radius });
        const pos3 = center.add(.{ .x = radius, .y = -radius });
        const scpos0 = frame.getCoords(pos0, self.viewport);
        const scpos1 = frame.getCoords(pos1, self.viewport);
        const scpos2 = frame.getCoords(pos2, self.viewport);
        const scpos3 = frame.getCoords(pos3, self.viewport);
        const v0 = VertexData{ .position = scpos0, .tex_coord = circleTexCoords[0], .color = circle.color };
        const v1 = VertexData{ .position = scpos1, .tex_coord = circleTexCoords[1], .color = circle.color };
        const v2 = VertexData{ .position = scpos2, .tex_coord = circleTexCoords[2], .color = circle.color };
        const v3 = VertexData{ .position = scpos3, .tex_coord = circleTexCoords[3], .color = circle.color };
        const base = @as(c_uint, @intCast(self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(circle.z_level).triangleVerts.items.len));
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(circle.z_level).triangleVerts.appendSlice(&[_]VertexData{ v0, v1, v2, v3 }) catch unreachable;
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(circle.z_level).indices.appendSlice(&[_]c_uint{ base + 0, base + 1, base + 3, base + 1, base + 2, base + 3 }) catch unreachable;
    }

    pub fn drawTriangle(self: *Self, tri: DrawTriangleOptions) void {
        const frame = tri.frame orelse self.frame;
        const p0 = tri.p0;
        const p1 = tri.p1;
        const p2 = tri.p2;
        const color = tri.color;
        const z_level = tri.z_level;
        const scpos0 = frame.getCoords(p0, self.viewport);
        const scpos1 = frame.getCoords(p1, self.viewport);
        const scpos2 = frame.getCoords(p2, self.viewport);
        const v0 = VertexData{ .position = scpos0, .color = color };
        const v1 = VertexData{ .position = scpos1, .color = color };
        const v2 = VertexData{ .position = scpos2, .color = color };
        const base = @as(c_uint, @intCast(self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.items.len));
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.appendSlice(&[_]VertexData{ v0, v1, v2 }) catch unreachable;
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).indices.appendSlice(&[_]c_uint{ base + 0, base + 1, base + 2 }) catch unreachable;
    }

    pub fn drawLine(self: *Self, line: DrawLineOptions) void {
        const frame = line.frame orelse self.frame;
        const p0 = line.p0;
        const p1 = line.p1;
        const width = line.width;
        const color = line.color;
        const z_level = line.z_level;
        const width_vec = p0.add(p1.scale(-1)).normalize().perpendicular().scale(0.5 * width);
        const pos0 = p0.add(width_vec);
        const pos1 = p0.add(width_vec.scale(-1));
        const pos2 = p1.add(width_vec.scale(-1));
        const pos3 = p1.add(width_vec);
        const scpos0 = frame.getCoords(pos0, self.viewport);
        const scpos1 = frame.getCoords(pos1, self.viewport);
        const scpos2 = frame.getCoords(pos2, self.viewport);
        const scpos3 = frame.getCoords(pos3, self.viewport);
        const v0 = VertexData{ .position = scpos0, .color = color };
        const v1 = VertexData{ .position = scpos1, .color = color };
        const v2 = VertexData{ .position = scpos2, .color = color };
        const v3 = VertexData{ .position = scpos3, .color = color };
        const base = @as(c_uint, @intCast(self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.items.len));
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.appendSlice(&[_]VertexData{ v0, v1, v2, v3 }) catch unreachable;
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).indices.appendSlice(&[_]c_uint{ base + 0, base + 1, base + 3, base + 1, base + 2, base + 3 }) catch unreachable;
    }

    pub fn drawRect(self: *Self, rect: DrawRectOptions) void {
        const frame = rect.frame orelse self.frame;
        var p0 = rect.p0;
        var p1 = rect.p1;
        switch (rect.anchor) {
            .absolute => {},
            .pos_size => {
                p1 = p0.add(p1);
            },
            .centered_size => {
                const half_size = p1.scale(0.5);
                p1 = p0.add(half_size);
                p0 = p0.add(half_size.scale(-1));
            },
            .y_centered_left => {
                const size = p1;
                p0 = p0.add(.{ .y = size.y * -0.5 });
                p1 = p0.add(size);
            },
            .left_top_relative => {
                const size = p1;
                p1 = p0.add(.{ .x = @abs(size.x), .y = @abs(size.y) });
            },
        }
        const color = rect.color;
        const z_level = rect.z_level;
        const pos0 = .{ .x = p0.x, .y = p0.y };
        const pos1 = .{ .x = p0.x, .y = p1.y };
        const pos2 = .{ .x = p1.x, .y = p1.y };
        const pos3 = .{ .x = p1.x, .y = p0.y };
        const scpos0 = frame.getCoords(pos0, self.viewport);
        const scpos1 = frame.getCoords(pos1, self.viewport);
        const scpos2 = frame.getCoords(pos2, self.viewport);
        const scpos3 = frame.getCoords(pos3, self.viewport);
        const v0 = VertexData{ .position = scpos0, .color = color };
        const v1 = VertexData{ .position = scpos1, .color = color };
        const v2 = VertexData{ .position = scpos2, .color = color };
        const v3 = VertexData{ .position = scpos3, .color = color };
        const base = @as(c_uint, @intCast(self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.items.len));
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).triangleVerts.appendSlice(&[_]VertexData{ v0, v1, v2, v3 }) catch unreachable;
        self.buffers[@intFromEnum(ShaderProgram.base)].getBuffer(z_level).indices.appendSlice(&[_]c_uint{ base + 0, base + 1, base + 3, base + 1, base + 2, base + 3 }) catch unreachable;
    }

    pub fn drawText(self: *Self, text: DrawTextOptions) void {
        var frame = text.frame orelse self.frame;
        const scale = text.scale;
        var pos = text.position;
        if (text.non_scaling) {
            if (frame.zoom != 1) {
                const screen_pos = frame.toScreenPos(pos);
                frame.zoom = 1;
                pos = frame.fromScreenPos(screen_pos, self.viewport);
            }
        }
        if (text.anchor == .bottom_center) {
            var width: f32 = 0;
            for (text.text) |char| {
                const glyph = self.chars.get(@as(u32, @intCast(char))).?;
                width += glyph.xadvance * scale;
            }
            pos = pos.add(.{ .x = -width / 2 });
        }
        const color = text.color;
        const z_level = text.z_level;
        for (text.text) |char| {
            const glyph = self.chars.get(@as(u32, @intCast(char))) orelse continue;
            const size = glyph.size.toVec2().scale(scale);
            const round_x = @floor((pos.x + (glyph.offset.x * scale)) + 0.5);
            const round_y = @floor((pos.y + (glyph.offset.y * scale)) + 0.5);
            const p0 = Vec2{ .x = round_x, .y = round_y };
            const p1 = p0.add(size);
            const pos0 = .{ .x = p0.x, .y = p0.y };
            const pos1 = .{ .x = p0.x, .y = p1.y };
            const pos2 = .{ .x = p1.x, .y = p1.y };
            const pos3 = .{ .x = p1.x, .y = p0.y };
            const scpos0 = frame.getCoords(pos0, self.viewport);
            const scpos1 = frame.getCoords(pos1, self.viewport);
            const scpos2 = frame.getCoords(pos2, self.viewport);
            const scpos3 = frame.getCoords(pos3, self.viewport);
            const v0 = VertexData{ .position = scpos0, .color = color, .tex_coord = .{ .x = glyph.tex0.x, .y = glyph.tex0.y } };
            const v1 = VertexData{ .position = scpos1, .color = color, .tex_coord = .{ .x = glyph.tex0.x, .y = glyph.tex1.y } };
            const v2 = VertexData{ .position = scpos2, .color = color, .tex_coord = .{ .x = glyph.tex1.x, .y = glyph.tex1.y } };
            const v3 = VertexData{ .position = scpos3, .color = color, .tex_coord = .{ .x = glyph.tex1.x, .y = glyph.tex0.y } };
            const base = @as(c_uint, @intCast(self.buffers[@intFromEnum(ShaderProgram.text)].getBuffer(z_level).triangleVerts.items.len));
            self.buffers[@intFromEnum(ShaderProgram.text)].getBuffer(z_level).triangleVerts.appendSlice(&[_]VertexData{ v0, v1, v2, v3 }) catch unreachable;
            self.buffers[@intFromEnum(ShaderProgram.text)].getBuffer(z_level).indices.appendSlice(&[_]c_uint{ base + 0, base + 1, base + 3, base + 1, base + 2, base + 3 }) catch unreachable;
            pos = pos.add(.{ .x = glyph.xadvance * scale });
        }
    }
};
