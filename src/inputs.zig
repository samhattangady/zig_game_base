const std = @import("std");
const build_options = @import("build_options");
const BUILDER_MODE = build_options.builder_mode;
const PLATFORM_LAYER = build_options.platform_layer;
const sokol = @import("sokol");
const sapp = sokol.app;

const helpers = @import("helpers.zig");
const Frame = @import("renderer.zig").Frame;
const ViewportData = @import("renderer.zig").ViewportData;
const Vec2 = helpers.Vec2;
const Vec2i = helpers.Vec2i;
const Rect = helpers.Rect;
const TYPING_BUFFER_SIZE = 16;
const Event = switch (PLATFORM_LAYER) {
    .sokol => sapp.Event,
    //   .sdl => c.SDL_Event,
};

const Keycode = enum(i32) {
    INVALID = 0,
    SPACE = 32,
    APOSTROPHE = 39,
    COMMA = 44,
    MINUS = 45,
    PERIOD = 46,
    SLASH = 47,
    _0 = 48,
    _1 = 49,
    _2 = 50,
    _3 = 51,
    _4 = 52,
    _5 = 53,
    _6 = 54,
    _7 = 55,
    _8 = 56,
    _9 = 57,
    SEMICOLON = 59,
    EQUAL = 61,
    A = 65,
    B = 66,
    C = 67,
    D = 68,
    E = 69,
    F = 70,
    G = 71,
    H = 72,
    I = 73,
    J = 74,
    K = 75,
    L = 76,
    M = 77,
    N = 78,
    O = 79,
    P = 80,
    Q = 81,
    R = 82,
    S = 83,
    T = 84,
    U = 85,
    V = 86,
    W = 87,
    X = 88,
    Y = 89,
    Z = 90,
    LEFT_BRACKET = 91,
    BACKSLASH = 92,
    RIGHT_BRACKET = 93,
    GRAVE_ACCENT = 96,
    WORLD_1 = 161,
    WORLD_2 = 162,
    ESCAPE = 256,
    ENTER = 257,
    TAB = 258,
    BACKSPACE = 259,
    INSERT = 260,
    DELETE = 261,
    RIGHT = 262,
    LEFT = 263,
    DOWN = 264,
    UP = 265,
    PAGE_UP = 266,
    PAGE_DOWN = 267,
    HOME = 268,
    END = 269,
    CAPS_LOCK = 280,
    SCROLL_LOCK = 281,
    NUM_LOCK = 282,
    PRINT_SCREEN = 283,
    PAUSE = 284,
    F1 = 290,
    F2 = 291,
    F3 = 292,
    F4 = 293,
    F5 = 294,
    F6 = 295,
    F7 = 296,
    F8 = 297,
    F9 = 298,
    F10 = 299,
    F11 = 300,
    F12 = 301,
    F13 = 302,
    F14 = 303,
    F15 = 304,
    F16 = 305,
    F17 = 306,
    F18 = 307,
    F19 = 308,
    F20 = 309,
    F21 = 310,
    F22 = 311,
    F23 = 312,
    F24 = 313,
    F25 = 314,
    KP_0 = 320,
    KP_1 = 321,
    KP_2 = 322,
    KP_3 = 323,
    KP_4 = 324,
    KP_5 = 325,
    KP_6 = 326,
    KP_7 = 327,
    KP_8 = 328,
    KP_9 = 329,
    KP_DECIMAL = 330,
    KP_DIVIDE = 331,
    KP_MULTIPLY = 332,
    KP_SUBTRACT = 333,
    KP_ADD = 334,
    KP_ENTER = 335,
    KP_EQUAL = 336,
    LEFT_SHIFT = 340,
    LEFT_CONTROL = 341,
    LEFT_ALT = 342,
    LEFT_SUPER = 343,
    RIGHT_SHIFT = 344,
    RIGHT_CONTROL = 345,
    RIGHT_ALT = 346,
    RIGHT_SUPER = 347,
    MENU = 348,
};
const INPUT_KEYS_COUNT = @typeInfo(Keycode).Enum.fields.len;

fn keyIndex(key: Keycode) usize {
    const enum_info = @typeInfo(@TypeOf(key));
    const enum_fields = enum_info.Enum.fields;
    inline for (enum_fields, 0..) |field, i| {
        if (std.mem.eql(u8, field.name, @tagName(key))) {
            return i;
        }
    }
    unreachable;
}

pub const Inputs = struct {
    const Self = @This();
    keys: [INPUT_KEYS_COUNT]SingleInput = [_]SingleInput{.{}} ** INPUT_KEYS_COUNT,
    mouse: MouseState = MouseState{},
    typed: [TYPING_BUFFER_SIZE]u8 = [_]u8{0} ** TYPING_BUFFER_SIZE,
    quit: bool = false,
    resize: ?Vec2i = null,
    num_typed: usize = 0,

    pub fn getKey(self: *const Self, key: Keycode) *const SingleInput {
        return &self.keys[keyIndex(key)];
    }

    pub fn getVarKey(self: *Self, key: Keycode) *SingleInput {
        return &self.keys[keyIndex(key)];
    }

    pub fn typeKey(self: *Self, k: u8) void {
        if (self.num_typed >= TYPING_BUFFER_SIZE) {
            helpers.debugPrint("Typing buffer already filled.\n", .{});
            return;
        }
        self.typed[self.num_typed] = k;
        self.num_typed += 1;
    }

    pub fn ctrlDown(self: *const Self) bool {
        return self.getKey(.LEFT_CONTROL).is_down or self.getKey(.RIGHT_CONTROL).is_down;
    }

    pub fn reset(self: *Self) void {
        for (&self.keys) |*key| key.reset();
        self.mouse.resetMouse();
        self.num_typed = 0;
        self.resize = null;
    }

    pub fn handleInputs(self: *Self, event: Event, ticks: u64) void {
        switch (PLATFORM_LAYER) {
            .sokol => self.handleInputsSokol(event, ticks),
            //.sdl => self.handleInputsSDL(event, ticks),
        }
    }

    fn getKeycode(self: *Self, keycode: sapp.Keycode) Keycode {
        _ = self;
        return @enumFromInt(@as(i32, @intFromEnum(keycode)));
    }

    fn handleInputsSokol(self: *Self, event: Event, ticks: u64) void {
        self.mouse.handleInput(event, ticks);
        if (event.type == .QUIT_REQUESTED) self.quit = true;
        if (event.type == .KEY_DOWN and event.key_code == .END) self.quit = true;
        if (event.type == .KEY_DOWN and event.key_code == .BACKSPACE) self.quit = true;
        if (event.type == .RESIZED) {
            self.resize = .{ .x = event.window_width, .y = event.window_height };
        }
        if (event.type == .KEY_DOWN) {
            self.keys[keyIndex(self.getKeycode(event.key_code))].setDown(ticks);
            // if (constants.BUILDER_MODE) if (helpers.get_char(event)) |k| self.type_key(k);
        } else if (event.type == .KEY_UP) {
            self.keys[keyIndex(self.getKeycode(event.key_code))].setRelease();
        }
    }
};

pub const SingleInput = struct {
    is_down: bool = false,
    is_clicked: bool = false, // For one frame when key is pressed
    is_released: bool = false, // For one frame when key is released
    down_from: u64 = 0,

    pub fn reset(self: *SingleInput) void {
        self.is_clicked = false;
        self.is_released = false;
    }

    pub fn setDown(self: *SingleInput, ticks: u64) void {
        self.is_down = true;
        self.is_clicked = true;
        self.down_from = ticks;
    }

    pub fn setRelease(self: *SingleInput) void {
        self.is_down = false;
        self.is_released = true;
    }
};

pub const MouseState = struct {
    const Self = @This();
    current_pos: Vec2 = .{},
    previous_pos: Vec2 = .{},
    l_down_pos: Vec2 = .{},
    r_down_pos: Vec2 = .{},
    m_down_pos: Vec2 = .{},
    l_button: SingleInput = .{},
    r_button: SingleInput = .{},
    m_button: SingleInput = .{},
    wheel_y: i32 = 0,

    pub fn resetMouse(self: *Self) void {
        self.previous_pos = self.current_pos;
        self.l_button.reset();
        self.r_button.reset();
        self.m_button.reset();
        self.wheel_y = 0;
    }

    pub fn lSinglePosClick(self: *Self) bool {
        if (self.l_button.is_released == false) return false;
        if (self.l_down_pos.distanceToSqr(self.current_pos) == 0) return true;
        return false;
    }

    pub fn lMoved(self: *Self) bool {
        return (self.l_down_pos.distanceToSqr(self.current_pos) > 0);
    }

    pub fn movement(self: *Self) Vec2 {
        return Vec2.subtract(self.previous_pos, self.current_pos);
    }

    pub fn handleInput(self: *Self, event: Event, ticks: u64) void {
        switch (PLATFORM_LAYER) {
            .sokol => self.handleInputSokol(event, ticks),
            //.sdl => self.handleInputSDL(event, ticks),
        }
    }

    pub fn handleInputSokol(self: *Self, event: Event, ticks: u64) void {
        switch (event.type) {
            .MOUSE_DOWN, .MOUSE_UP => {
                const button = switch (event.mouse_button) {
                    .LEFT => &self.l_button,
                    .RIGHT => &self.r_button,
                    .MIDDLE => &self.m_button,
                    else => &self.l_button,
                };
                const pos = switch (event.mouse_button) {
                    .LEFT => &self.l_down_pos,
                    .RIGHT => &self.r_down_pos,
                    .MIDDLE => &self.m_down_pos,
                    else => &self.l_down_pos,
                };
                if (event.type == .MOUSE_DOWN) {
                    pos.* = self.current_pos;
                    button.is_down = true;
                    button.is_clicked = true;
                    button.down_from = ticks;
                }
                if (event.type == .MOUSE_UP) {
                    button.is_down = false;
                    button.is_released = true;
                }
            },
            .MOUSE_SCROLL => {
                self.wheel_y = @intFromFloat(event.scroll_y);
            },
            .MOUSE_MOVE => {
                self.current_pos = .{ .x = event.mouse_x, .y = event.mouse_y };
            },
            else => {},
        }
    }
};

pub const Button = struct {
    const Self = @This();
    rect: Rect,
    text: []const u8 = "",
    mouse_over: bool = false,
    hovered: bool = false,
    disabled: bool = false,
    highlighted: bool = false,
    hidden: bool = false,
    /// mouse is down and was clicked down within the bounds of the button
    triggered: bool = false,
    /// mouse was clicked in button on this frame.
    just_clicked: bool = false,
    /// mouse was clicked and released within bounds of button
    clicked: bool = false,
    r_clicked: bool = false,
    m_clicked: bool = false,
    value: i8 = 0,

    pub fn update(self: *Self, mouse: *const MouseState, frame: Frame, viewport: ViewportData) void {
        if (self.disabled) return;
        self.mouse_over = self.inBounds(mouse.current_pos, frame, viewport);
        self.hovered = !mouse.l_button.is_down and self.mouse_over;
        self.clicked = mouse.l_button.is_released and self.inBounds(mouse.l_down_pos, frame, viewport) and self.inBounds(mouse.current_pos, frame, viewport);
        self.triggered = mouse.l_button.is_down and self.inBounds(mouse.l_down_pos, frame, viewport);
        self.just_clicked = mouse.l_button.is_clicked and self.inBounds(mouse.current_pos, frame, viewport);
        self.m_clicked = mouse.m_button.is_released and self.inBounds(mouse.m_down_pos, frame, viewport) and self.inBounds(mouse.current_pos, frame, viewport);
        self.r_clicked = mouse.r_button.is_released and self.inBounds(mouse.r_down_pos, frame, viewport) and self.inBounds(mouse.current_pos, frame, viewport);
    }

    // This is probably not needed because update state will have l_button.is_released as false anyway
    pub fn reset(self: *Self) void {
        self.clicked = false;
        self.r_clicked = false;
        self.m_clicked = false;
    }

    pub fn disable(self: *Self) void {
        self.disabled = true;
        self.hovered = false;
        self.triggered = false;
        self.clicked = false;
        self.r_clicked = false;
        self.m_clicked = false;
    }

    pub fn enable(self: *Self) void {
        self.disabled = false;
    }

    fn inBounds(self: *const Self, pos: Vec2, frame: Frame, viewport: ViewportData) bool {
        const world_pos = frame.fromScreenPos(pos, viewport);
        return helpers.inBoxCentered(world_pos, self.rect.position, self.rect.size);
    }
};
