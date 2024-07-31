const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const BUILDER_MODE = build_options.builder_mode;
const SUPER_ASSERT_MODE = build_options.super_assert_mode;

const helpers = @import("helpers.zig");
const Vec2 = helpers.Vec2;
const Hex = helpers.Hex;
const inputsLib = @import("inputs.zig");
const Inputs = inputsLib.Inputs;
const ViewportData = @import("renderer.zig").ViewportData;
const Frame = @import("renderer.zig").Frame;

pub const ControlCommand = struct {};

pub const Simulation = struct {
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator) Simulation {
        return .{ .allocator = allocator, .arena = arena };
    }

    pub fn setup(self: *Simulation) void {
        _ = self;
    }

    pub fn deinit(self: *Simulation) void {
        _ = self;
    }

    pub fn resetSim(self: *Simulation) void {
        _ = self;
    }

    pub fn endFrame(self: *Simulation) void {
        _ = self;
    }

    pub fn sendCommand(self: *Simulation, command: ControlCommand) void {
        _ = self;
        _ = command;
    }
};
