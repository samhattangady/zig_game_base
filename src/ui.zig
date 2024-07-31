const std = @import("std");
const c = @import("c.zig");
const build_options = @import("build_options");
const BUILDER_MODE = build_options.builder_mode;
const SCREEN_SIZE = @import("renderer.zig").SCREEN_SIZE;
const Frame = @import("renderer.zig").Frame;
const ViewportData = @import("renderer.zig").ViewportData;

const helpers = @import("helpers.zig");
const Vec2 = helpers.Vec2;
const Vec2i = helpers.Vec2i;
const Vec3 = helpers.Vec3;
const Vec4 = helpers.Vec4;
const Rect = helpers.Rect;
const Circle = helpers.Circle;
const ConstIndexArray = helpers.ConstIndexArray;
const colors = @import("colors.zig");
const HOTRELOAD = build_options.hotreload;
const Control = @import("control.zig").Control;
const ZoneIndex = usize;
const sim_lib = @import("simulation.zig");
const Simulation = sim_lib.Simulation;
const StructureKey = sim_lib.StructureKey;
const ControlCommand = sim_lib.ControlCommand;
const Renderer = @import("renderer.zig").Renderer;
const CharData = @import("renderer.zig").CharData;
const X_PADDING = 20;
const Y_PADDING = 10;
const Y_ROW = 20;
const UI_TEXT_SCALE = 0.6;

const inputs_lib = @import("inputs.zig");
const Inputs = inputs_lib.Inputs;
const MouseState = inputs_lib.MouseState;

// Manually done to be below the contract tab, and above the bottom toolbalr.
const DEFAULT_WINDOW_P0 = Vec2{ .x = SCREEN_SIZE.x * 0.7, .y = TOPBAR_RECT.position.y + TOPBAR_RECT.size.y + 200 + 25 };
const DEFAULT_WINDOW_P1 = Vec2{ .x = SCREEN_SIZE.x * 0.99, .y = SCREEN_SIZE.y * 0.935 };
const PADDING = Vec2{ .x = X_PADDING, .y = Y_PADDING + Y_ROW };
const TOOLBAR_RECT = Rect{
    .position = .{ .x = SCREEN_SIZE.x * 0.05, .y = SCREEN_SIZE.y * 0.94 },
    .size = .{ .x = SCREEN_SIZE.x * 0.9, .y = SCREEN_SIZE.y * 0.04 + Y_PADDING },
};
const TOPBAR_RECT = Rect{
    .position = .{ .x = SCREEN_SIZE.x * 0.05, .y = SCREEN_SIZE.y * 0.01 },
    .size = .{ .x = SCREEN_SIZE.x * 0.9, .y = SCREEN_SIZE.y * 0.04 + Y_PADDING },
};
const Y_TEXT = -4;

pub const ToolTip = struct {
    rect: Rect,
    text: []const u8,
};

const WindowType = union(enum) {
    toolbar: void,
};

const Window = struct {
    window: WindowType,
    rect: Rect,
};

const WidgetType = enum {
    label,
    checkbox,
    button,
    menu,
    blank,

    pub fn hasXPadding(self: *const WidgetType) bool {
        return switch (self.*) {
            .label,
            .checkbox,
            .blank,
            => false,
            .button,
            .menu,
            => true,
        };
    }
};
const Widget = struct {
    widget: WidgetType,
    text: []const u8,
    rect: Rect,
    // for checkboxes etc. where the clickable area is different from rect
    clickable: ?Rect = null,
    value: ?bool = null,
    hovered: bool = false,
};

pub const Ui = struct {
    tooltip: ?ToolTip = null,
    windows: std.ArrayList(Window),
    widgets: std.ArrayList(Widget),
    chars: *const std.AutoHashMap(u32, CharData),
    position: Vec2,
    open_window: ?WindowType = null,
    mouse: MouseState = undefined,
    allocator: std.mem.Allocator,
    frame: Frame = undefined,
    viewport: ViewportData = undefined,
    hovered: bool = false,
    prev_row_x: f32 = DEFAULT_WINDOW_P0.x,
    // custom arena that is just used by the ui
    arena_handle: std.heap.ArenaAllocator,
    arena: std.mem.Allocator,
    quests_open: bool = true,
    build_menu: bool = false,
    automation_menu: bool = false,
    sensors_menu: bool = false,
    window_menu0: bool = false,
    window_menu1: bool = false,

    pub fn init(allocator: std.mem.Allocator) Ui {
        var arena_handle = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var self = Ui{
            .windows = std.ArrayList(Window).init(allocator),
            .widgets = std.ArrayList(Widget).init(allocator),
            .chars = undefined,
            .position = DEFAULT_WINDOW_P0.add(.{ .x = X_PADDING, .y = Y_PADDING + Y_ROW }),
            .allocator = allocator,
            .arena_handle = arena_handle,
            .arena = arena_handle.allocator(),
        };
        self.windows.append(.{ .window = .toolbar, .rect = TOOLBAR_RECT }) catch unreachable;
        return self;
    }

    pub fn deinit(self: *Ui) void {
        self.windows.deinit();
        self.widgets.deinit();
        self.arena_handle.deinit();
    }

    pub fn reset(self: *Ui) void {
        self.windows.clearRetainingCapacity();
        self.windows.append(.{ .window = .toolbar, .rect = TOOLBAR_RECT }) catch unreachable;
    }

    pub fn closeMenus(self: *Ui) void {
        self.build_menu = false;
        self.automation_menu = false;
        self.sensors_menu = false;
    }

    pub fn openPumpWindow(self: *Ui, skey: StructureKey) void {
        self.closeAdditionalWindows(self.arena);
        self.windows.append(.{ .window = .{ .liquid_pump = skey }, .rect = self.defaultWindow() }) catch unreachable;
    }

    pub fn update(self: *Ui, arena: std.mem.Allocator, control: *Control, inputs: Inputs, frame: Frame, viewport: ViewportData) void {
        _ = frame;
        // ui has its own frame that is different from the game frame, because ui will always be
        // anchored to the screen, and unaffated by zoom.
        self.frame = .{};
        self.arena = arena;
        self.viewport = viewport;
        self.position = DEFAULT_WINDOW_P0.add(.{ .x = X_PADDING, .y = Y_PADDING + Y_ROW });
        self.widgets.clearRetainingCapacity();
        self.mouse = inputs.mouse;
        create_ui: {
            for (self.windows.items) |window| {
                self.position = window.rect.position.add(PADDING);
                switch (window.window) {
                    .toolbar => {
                        if (self.button("Pump", .{})) {
                            control.setMode(.build_pump);
                        }
                        if (self.button("Add Salt 0", .{})) {
                            control.setMode(.add_salt);
                            control.mode_data.index = 0;
                        }
                        if (self.button("Add Salt 1", .{})) {
                            control.setMode(.add_salt);
                            control.mode_data.index = 1;
                        }
                    },
                    .liquid_pump => |skey| {
                        const pump_structure = control.sim.structures.getConstPtr(skey);
                        const pump = control.sim.liquids.getPumpAt(pump_structure.address).?;
                        self.position = DEFAULT_WINDOW_P0;
                        self.blank(DEFAULT_WINDOW_P1.subtract(DEFAULT_WINDOW_P0));
                        self.label("Pump {d}", .{skey.index});
                        self.newLine();
                        const command = ControlCommand{ .command = .liquid_pump_toggle, .address = pump_structure.address, .structure = skey };
                        const button_text = if (pump.enabled) "Stop Pumping" else "Start Pumping";
                        if (self.button("{s}", .{button_text})) control.sendCommand(command);
                    },
                }
            }
            break :create_ui;
        }
        self.hovered = self.isHovered();
        if (self.mouse.l_button.is_clicked) self.closeAdditionalWindows(self.arena);
        if (inputs.getKey(.ESCAPE).is_clicked) self.closeMenus();
    }

    pub fn endFrame(self: *Ui) void {
        self.tooltip = null;
        _ = self.arena_handle.reset(.retain_capacity);
        self.arena = self.arena_handle.allocator();
    }

    pub fn prevWidth(self: *Ui) f32 {
        if (self.widgets.items.len == 0) unreachable; // no widgets added yet
        return self.widgets.getLast().rect.size.x;
    }

    fn closeAdditionalWindows(self: *Ui, arena: std.mem.Allocator) void {
        // TODO (27 Feb 2024 sam): close window_menu0 here somewhere.
        const ui_pos = self.uiPos();
        var to_close = std.ArrayList(usize).init(arena);
        for (self.windows.items, 0..) |win, i| {
            if (!win.window.closable()) continue;
            if (!win.rect.contains(ui_pos)) to_close.insert(0, i) catch unreachable;
        }
        for (to_close.items) |i| _ = self.windows.orderedRemove(i);
        // TODO (08 Feb 2024 sam): Be a little more thorough here. If its not in the menu blank,
        // then close the menu
        if (!self.hovered) {
            self.build_menu = false;
            self.automation_menu = false;
        }
    }

    pub fn isHovered(self: *const Ui) bool {
        const ui_pos = self.uiPos();
        for (self.windows.items) |win| {
            if (win.rect.contains(ui_pos)) return true;
        }
        for (self.widgets.items) |wid| {
            if (wid.rect.contains(ui_pos)) return true;
        }
        return false;
    }

    fn defaultWindow(self: *Ui) Rect {
        _ = self;
        return .{
            .position = DEFAULT_WINDOW_P0,
            .size = DEFAULT_WINDOW_P1.subtract(DEFAULT_WINDOW_P0),
        };
    }

    pub fn getTextWidth(self: *Ui, text: []const u8) f32 {
        var width: f32 = 0;
        for (text) |char| {
            const glyph = self.chars.get(@as(u32, @intCast(char))).?;
            width += glyph.xadvance * UI_TEXT_SCALE;
        }
        return width;
    }

    fn uiPos(self: *const Ui) Vec2 {
        return self.frame.fromScreenPos(self.mouse.current_pos, self.viewport);
    }

    fn horizontalSpacer(self: *Ui, count: f32) void {
        self.position = self.position.add(.{ .x = X_PADDING * count });
    }

    // just a background. useful for menus and things
    fn blank(self: *Ui, size: Vec2) void {
        self.widgets.append(.{
            .widget = .blank,
            .text = "",
            .rect = .{
                .position = self.position,
                .size = size,
            },
        }) catch unreachable;
        self.position = self.position.add(.{ .y = Y_ROW * 1.5, .x = X_PADDING });
    }

    pub fn label(self: *Ui, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch unreachable;
        const width = self.getTextWidth(text);
        self.widgets.append(.{
            .widget = .label,
            .text = text,
            .rect = .{
                .position = self.position,
                .size = .{ .x = width, .y = -Y_ROW },
            },
        }) catch unreachable;
        self.position = self.position.add(.{ .x = width + X_PADDING });
    }

    fn button(self: *Ui, comptime fmt: []const u8, args: anytype) bool {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch unreachable;
        const width = self.getTextWidth(text);
        const rect = Rect{
            .position = self.position,
            .size = .{ .x = width + (X_PADDING * 1), .y = -Y_ROW },
        };
        const hovered = rect.contains(self.uiPos());
        self.widgets.append(.{
            .widget = .button,
            .text = text,
            .rect = rect,
            .clickable = rect,
            .hovered = hovered,
        }) catch unreachable;
        self.position = self.position.add(.{ .x = rect.size.x + X_PADDING });
        return self.mouse.l_button.is_clicked and hovered;
    }

    fn menu(self: *Ui, comptime fmt: []const u8, args: anytype, open: *bool, r_click_close: bool) bool {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch unreachable;
        const width = self.getTextWidth(text);
        const rect = Rect{
            .position = self.position,
            .size = .{ .x = width + (X_PADDING * 1), .y = -Y_ROW },
        };
        const hovered = rect.contains(self.uiPos());
        self.widgets.append(.{
            .widget = .menu,
            .text = text,
            .rect = rect,
            .clickable = rect,
            .hovered = hovered,
        }) catch unreachable;
        self.position = self.position.add(.{ .x = rect.size.x + X_PADDING });
        if (self.mouse.l_button.is_clicked and hovered) open.* = !open.*;
        if (r_click_close and self.mouse.r_button.is_clicked and open.*) open.* = !open.*;
        return open.*;
    }

    pub fn checkbox(self: *Ui, comptime fmt: []const u8, args: anytype, on: *const bool) bool {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch unreachable;
        const width = self.getTextWidth(text);
        const clickable = Rect{ .position = self.position, .size = .{ .x = Y_ROW, .y = -Y_ROW } };
        const hovered = clickable.contains(self.uiPos());
        self.widgets.append(.{
            .widget = .checkbox,
            .text = text,
            .rect = .{
                .position = self.position.add(.{ .x = Y_ROW + X_PADDING }),
                .size = .{ .x = width, .y = -Y_ROW },
            },
            .clickable = clickable,
            .value = on.*,
            .hovered = hovered,
        }) catch unreachable;
        self.position = self.position.add(.{ .x = width + X_PADDING + Y_ROW + X_PADDING });
        return self.mouse.l_button.is_clicked and hovered;
    }

    pub fn newLine(self: *Ui) void {
        self.position = .{ .x = self.prev_row_x + X_PADDING, .y = self.position.y + Y_PADDING + Y_ROW };
    }

    pub fn halfLine(self: *Ui) void {
        self.position = .{ .x = self.prev_row_x + X_PADDING, .y = self.position.y + Y_PADDING };
    }

    pub fn setTooltip(self: *Ui, position: Vec2, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch unreachable;
        self.tooltip = .{
            .rect = .{ .position = position, .size = .{ .x = @max(100, self.getTextWidth(text) * 0.6 + 16), .y = -18 } },
            .text = text,
        };
    }

    pub fn render(self: *Ui, renderer: *Renderer) void {
        const initial_frame = renderer.frame;
        renderer.setFrame(.{});
        defer renderer.setFrame(initial_frame);
        for (self.windows.items) |window| {
            renderer.drawRect(.{
                .p0 = window.rect.position,
                .p1 = window.rect.position.add(window.rect.size),
                .color = colors.solarized_base03,
            });
        }
        for (self.widgets.items) |widget| {
            if (widget.widget == .blank) {
                renderer.drawRect(.{
                    .p0 = widget.rect.position,
                    .p1 = widget.rect.position.add(widget.rect.size),
                    .color = colors.solarized_base03,
                });
            }
            if (widget.clickable) |rect| {
                {
                    const color = if (widget.hovered) colors.white.alpha(0.3) else colors.white.alpha(0.2);
                    renderer.drawRect(.{
                        .p0 = rect.position,
                        .p1 = rect.size,
                        .color = color,
                        .anchor = .pos_size,
                    });
                }
                if (widget.value) |val| {
                    const color = if (val) colors.solarized_blue.alpha(0.8) else colors.solarized_base03.alpha(0);
                    renderer.drawRect(.{
                        .p0 = rect.position.add(.{ .x = 2, .y = -2 }),
                        .p1 = rect.size.add(.{ .x = -4, .y = 4 }),
                        .color = color,
                        .anchor = .pos_size,
                    });
                }
            }
            const padding: f32 = if (widget.widget.hasXPadding()) X_PADDING * 0.5 else 0;
            renderer.drawText(.{
                .text = widget.text,
                .position = widget.rect.position.add(.{ .x = padding, .y = Y_TEXT }),
                .scale = UI_TEXT_SCALE,
                .color = colors.white,
                .anchor = .bottom_left,
            });
        }
    }
};
