const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const BUILDER_MODE = build_options.builder_mode;
const SUPER_ASSERT_MODE = build_options.super_assert_mode;

const helpers = @import("helpers.zig");
const Vec2 = helpers.Vec2;
const Vec2i = helpers.Vec2i;
const inputsLib = @import("inputs.zig");
const Inputs = inputsLib.Inputs;
const ViewportData = @import("renderer.zig").ViewportData;
const Frame = @import("renderer.zig").Frame;
const ui_lib = @import("ui.zig");
const Ui = ui_lib.Ui;
const ControlCommand = @import("simulation.zig").ControlCommand;
const Simulation = @import("simulation.zig").Simulation;
const Orientation = helpers.Orientation;

pub const ControlMode = enum {
    idle,
};

pub const ControlModeData = struct {
    address: Vec2i = undefined,
    orientation: Orientation = .n,
    index: usize = 0,
};

pub const Control = struct {
    hovered: Vec2i = .{},
    mode: ControlMode = .idle,
    mode_data: ControlModeData = .{},
    ui: Ui,
    sim: *Simulation,
    valid: bool = true,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator) Control {
        return .{
            .sim = undefined,
            .ui = Ui.init(allocator),
            .allocator = allocator,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Control) void {
        self.ui.deinit();
    }

    pub fn setMode(self: *Control, mode: ControlMode) void {
        self.mode = mode;
    }

    pub fn sendCommand(self: *Control, command: ControlCommand) void {
        self.sim.addCommand(command);
    }

    pub fn reset(self: *Control) void {
        self.mode = .idle;
        self.ui.reset();
    }

    pub fn update(self: *Control, inputs: Inputs, frame: Frame, viewport: ViewportData, arena: std.mem.Allocator) void {
        self.arena = arena;
        // const position = frame.fromScreenPos(inputs.mouse.current_pos, viewport);
        // const address = Hex.indexFromPos(position);
        // self.valid = true;
        // self.hovered = address;
        // self.mode_data.address = address;
        self.ui.update(arena, self, inputs, frame, viewport);
        if (!self.ui.hovered) {
            switch (self.mode) {
                .idle => {},
            }
        }
        if (BUILDER_MODE) {}
    }

    pub fn endFrame(self: *Control) void {
        self.ui.endFrame();
    }
};
