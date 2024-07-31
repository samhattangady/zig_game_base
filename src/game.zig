const std = @import("std");
const build_options = @import("build_options");
const ztracy = @import("ztracy");
const BUILDER_MODE = build_options.builder_mode;
const Renderer = @import("renderer.zig").Renderer;
const VertexData = @import("renderer.zig").VertexData;
const SCREEN_SIZE = @import("renderer.zig").SCREEN_SIZE;
const ViewportData = @import("renderer.zig").ViewportData;
const Frame = @import("renderer.zig").Frame;
const serializer = @import("serializer.zig");

const helpers = @import("helpers.zig");
const Vec2 = helpers.Vec2;
const Vec2i = helpers.Vec2i;
const Vec3 = helpers.Vec3;
const Vec4 = helpers.Vec4;
const Rect = helpers.Rect;
const Circle = helpers.Circle;
const Triangle = helpers.Triangle;
const colors = @import("colors.zig");
const HOTRELOAD = build_options.hotreload;

const inputsLib = @import("inputs.zig");
const Inputs = inputsLib.Inputs;
const sim_lib = @import("simulation.zig");
const Simulation = sim_lib.Simulation;
const Control = @import("control.zig").Control;

const DebugData = struct {
    point: ?Vec2 = null,
    highlight: std.ArrayList(Vec2),
    frame_timer: ?[]u8 = null,
    show: bool = false,

    pub fn init(allocator: std.mem.Allocator) DebugData {
        return .{
            .highlight = std.ArrayList(Vec2).init(allocator),
        };
    }
};

pub const Game = struct {
    renderer: Renderer,
    ticks: u64 = 0,
    prev_ticks: u64 = 0,
    prev_save: u64 = 0,
    /// external flag to signal that there has been a reload
    reload: if (HOTRELOAD) bool else void = if (HOTRELOAD) false else {},
    should_quit: bool = false,
    inputs: Inputs = .{},
    frame: Frame = .{},
    ui_frame: Frame = .{},
    viewport: ViewportData = undefined,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    /// Mostly to deal with some lib v exe jank. We want the setup to be run by the lib, not the
    /// exe. This also keeps the init time to be very fast, which might be useful in quick first
    /// render.
    setup_complete: bool = false,
    debug: if (BUILDER_MODE) DebugData else void = undefined,
    progress: f32 = 0,
    num_steps_per_tick: u8 = 1,
    terrain_updated: bool = true,

    control: Control,
    sim: Simulation,

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator, viewport: ViewportData) !Game {
        const renderer = Renderer.init(allocator, arena, viewport);
        const self = Game{
            .renderer = renderer,
            .viewport = viewport,
            .sim = Simulation.init(allocator, arena),
            .control = Control.init(allocator, arena),
            .allocator = allocator,
            .arena = arena,
        };
        return self;
    }

    pub fn deinit(self: *Game) void {
        self.renderer.deinit();
        self.sim.deinit();
        self.control.deinit();
    }

    fn setup(self: *Game) void {
        self.sim.setup();
        self.setup_complete = true;
    }

    pub fn endFrame(self: *Game) void {
        self.control.endFrame();
        self.sim.endFrame();
    }

    pub fn resetSim(self: *Game) void {
        self.sim.resetSim();
        self.control.reset();
    }

    pub fn update(self: *Game, ticks: u64, viewport: ViewportData, arena: std.mem.Allocator, inputs: Inputs) void {
        const tracy_zone = ztracy.Zone(@src());
        defer tracy_zone.End();
        self.renderer.terrain_update = false;
        self.inputs = inputs;
        self.prev_ticks = self.ticks;
        self.ticks = ticks;
        self.arena = arena;
        if (HOTRELOAD and self.reload) self.setReloadedState();
        if (!self.setup_complete) self.setup();
        self.viewport = viewport;
        self.renderer.viewport = viewport;
        self.should_quit = self.inputs.quit;
        self.renderer.update_window = self.inputs.resize;
        //  self.control.update(self.inputs, self.frame, viewport, self.arena);
        // if (self.ticks - self.prev_save > SAVE_FREQUENCY_TICKS) {
        //     self.saveGame();
        //     self.prev_save = self.ticks;
        // }
        // if (inputs.getKey(.S).is_clicked and inputs.getKey(.LEFT_CONTROL).is_down) {
        //     self.saveGame();
        // }
        // if (inputs.getKey(.L).is_clicked and inputs.getKey(.LEFT_CONTROL).is_down) {
        //     self.loadGame("data/savefiles/save.json");
        // }
        // if (inputs.getKey(.R).is_clicked and inputs.getKey(.LEFT_CONTROL).is_down) {
        //     self.resetSim();
        // }
        // for (0..self.num_steps_per_tick) |_| {
        //     self.handleZoomMouseControls();
        //     const world_pos = self.frame.fromScreenPos(self.inputs.mouse.current_pos, self.viewport);
        //     switch (self.mode) {
        //         .sim_trails => {
        //             self.sim.update(self.arena);
        //         },
        //     }
        //     if (BUILDER_MODE) {
        //         if (self.inputs.getKey(.F).is_clicked) self.renderer.toggleFullScreen();
        //         if (self.inputs.getKey(.EQUAL).is_clicked) self.num_steps_per_tick += 1;
        //         if (self.inputs.getKey(.MINUS).is_clicked) {
        //             if (self.num_steps_per_tick > 1) self.num_steps_per_tick -= 1;
        //         }
        //         self.debug = DebugData.init(self.arena);
        //         self.debug.frame_timer = std.fmt.allocPrint(self.arena, "{d} ms", .{self.ticks - self.prev_ticks}) catch unreachable;
        //         if (false) {
        //             const ants_1 = self.ant_qtree.getAll(.{}, .{ .circle = Circle.centeredAt(world_pos, 50) }, self.arena, null);
        //             for (ants_1.items) |ant| {
        //                 self.debug.highlight.append(ant.position) catch unreachable;
        //             }
        //         }
        //         self.debug.show = self.inputs.getKey(.SPACE).is_down;
        //         if (false and self.inputs.mouse.l_button.is_clicked) {
        //             const current = Hex.indexFromPos(world_pos);
        //             helpers.debugPrint("{d}, {d}\n", .{ current.q, current.r });
        //         }
        //     }
        self.inputs.reset();
        // }
    }

    fn setReloadedState(self: *Game) void {
        self.reload = false;
    }

    fn handleMouseInputs(self: *Game) void {
        _ = self;
    }

    pub fn fillBuffers(self: *Game) void {
        const tracy_zone = ztracy.ZoneN(@src(), "game.fillBuffers");
        defer tracy_zone.End();
        if (!self.setup_complete) return;
        self.renderer.clearBuffers();
        self.renderer.frame = self.frame;
        // switch (self.mode) {
        //     .sim_trails => self.renderTrails(),
        // }
        if (true) {
            const color = if (self.inputs.getKey(.SPACE).is_down) colors.solarized_base03 else colors.solarized_base3;
            self.renderer.drawCircle(.{ .position = self.inputs.mouse.current_pos, .radius = 5, .color = color, .frame = .{} });
        }
        if (BUILDER_MODE) {
            self.progress += 1;
            if (true) {
                const pos = Vec2{ .x = @mod(self.progress, SCREEN_SIZE.x), .y = 1 };
                self.renderer.drawCircle(.{ .position = pos, .radius = 5, .color = colors.solarized_green.alpha(0.1), .frame = .{} });
            }
            if (self.debug.point) |pos| {
                self.renderer.drawCircle(.{ .position = pos, .radius = 10, .color = colors.solarized_green });
            }
            for (self.debug.highlight.items) |pos|
                self.renderer.drawCircle(.{ .position = pos, .radius = 10, .color = colors.solarized_green });
            if (self.debug.frame_timer) |text| self.renderer.drawText(.{ .text = text, .position = .{ .x = 10, .y = 15 }, .color = colors.black, .scale = 0.5, .frame = .{}, .anchor = .bottom_left });
            if (self.ticks - self.prev_ticks > 17) {
                self.renderer.drawRect(.{
                    .p0 = self.frame.origin,
                    .p1 = .{ .x = 200, .y = 200 },
                    .color = colors.solarized_red.alpha(0.6),
                    .anchor = .pos_size,
                });
            }
        }
        //if (self.control.mode.orientationRelevant()) {
        //    const address = self.control.mode_data.address;
        //    const orientation = self.control.mode_data.orientation;
        //    self.drawArrow(address, orientation, .out, colors.solarized_base0, 0.8);
        //}
    }
};

pub export fn gameUpdateFrameDynamic(game: *Game, ticks: u64, viewport_ptr: *anyopaque, arena_ptr: *anyopaque, inputs_ptr: *anyopaque) void {
    const arena: *std.mem.Allocator = @alignCast(@ptrCast(arena_ptr));
    const viewport: *ViewportData = @alignCast(@ptrCast(viewport_ptr));
    const inputs: *Inputs = @alignCast(@ptrCast(inputs_ptr));
    game.update(ticks, viewport.*, arena.*, inputs.*);
}

pub export fn gamePresentFrameDynamic(game: *Game) void {
    game.fillBuffers();
    game.endFrame();
}
