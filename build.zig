const std = @import("std");
const builtin = @import("builtin");
const TRACY_PATH = "C:\\Users\\user\\libraries\\tracy-0.9.1";
const BUILD_C_SOURCE_CODE = false;

pub const BuildMode = enum {
    /// Build static executable
    static_exe,
    /// Build dynamic executable and dynamic library
    dynamic_exe,
    /// Build dynamic library
    hotreload,
};

pub const PlatformLayer = enum {
    sokol,
    //sdl,
};

pub fn build(b: *std.Build) void {
    const is_windows = builtin.os.tag == .windows;
    // var target = b.standardTargetOptions(.{});
    const target_query = if (is_windows)
        std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-windows-gnu" }) catch unreachable
    else
        std.zig.CrossTarget.parse(.{ .arch_os_abi = "aarch64-macos-none" }) catch unreachable;
    const target = b.resolveTargetQuery(target_query);
    const optimize = b.standardOptimizeOption(.{});
    const znoise = b.dependency("znoise", .{
        .target = target,
        .optimize = optimize,
    });
    const ztracy = b.dependency("ztracy", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    // There are two ways to build the app: with hot-reloading enabled, and without
    // In the case of hot-reloading, there are two relevant commands:
    // zig build run and zig build reload
    // zig build reload automatically assumes that the hotreload is true
    // zig build run defaults to hotreload is false - and it always builds the executable

    const build_mode = b.option(BuildMode, "build_mode", "Can be static_exe, dynamic_exe or hotreload") orelse .static_exe;
    const builder_mode = b.option(bool, "builder", "Build project with developer tools") orelse true;
    const super_assert_mode = b.option(bool, "superassert", "Assert ALL THE THINGS") orelse true;
    const platform_layer = b.option(PlatformLayer, "platform_layer", "Supports sokol and sdl") orelse .sokol;
    const enable_ztracy = b.option(bool, "ztracy", "Enable tracy profiler") orelse false;
    const test_filter = b.option([]const u8, "test_filter", "Text filter for tests");
    // const ztracy_pkg = ztracy.package(b, target, optimize, .{
    //     .options = .{ .enable_ztracy = enable_ztracy },
    // });

    const build_exe = (build_mode == .static_exe or build_mode == .dynamic_exe);
    const build_lib = (build_mode == .hotreload or build_mode == .dynamic_exe);
    const hotreload = build_lib;
    if (hotreload and enable_ztracy) {
        std.debug.print("Don't trace while hotreloading da waste fellow\n", .{});
        unreachable; // trying to use tracy in hotreload mode. no point
    }

    var options = b.addOptions();
    options.addOption(bool, "builder_mode", builder_mode);
    options.addOption(bool, "super_assert_mode", super_assert_mode);
    options.addOption(bool, "hotreload", hotreload);
    options.addOption(PlatformLayer, "platform_layer", platform_layer);

    if (BUILD_C_SOURCE_CODE) target.ofmt = .c;
    const exe = b.addExecutable(.{
        .name = "forestorio",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    exe.addSystemIncludePath(.{ .path = "src" });
    exe.root_module.addOptions("build_options", options);
    if (platform_layer == .sokol) {
        exe.root_module.addImport("sokol", sokol.module("sokol"));
    }
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));
    exe.root_module.addImport("ztracy", ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    const lib = b.addSharedLibrary(.{
        .name = "forestorio",
        .root_source_file = .{ .path = "src/game.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addSystemIncludePath(.{ .path = "src" });
    lib.root_module.addOptions("build_options", options);
    lib.root_module.addImport("znoise", znoise.module("root"));
    lib.linkLibrary(znoise.artifact("FastNoiseLite"));
    lib.root_module.addImport("ztracy", ztracy.module("root"));
    lib.linkLibrary(ztracy.artifact("tracy"));
    //ztracy_pkg.link(lib);

    if (build_exe) {
        //     if (is_windows) b.installBinFile("C:/SDL2-2.26.5/lib/x64/SDL2.dll", "SDL2.dll");
        b.installArtifact(exe);
    }

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    if (build_lib) {
        b.installArtifact(lib);
    }

    const sim_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
        .filter = test_filter,
    });
    sim_unit_tests.addSystemIncludePath(.{ .path = "src" });
    sim_unit_tests.root_module.addOptions("build_options", options);
    sim_unit_tests.root_module.addImport("znoise", znoise.module("root"));
    sim_unit_tests.linkLibrary(znoise.artifact("FastNoiseLite"));
    sim_unit_tests.root_module.addImport("ztracy", ztracy.module("root"));
    sim_unit_tests.linkLibrary(ztracy.artifact("tracy"));
    const run_sim_unit_tests = b.addRunArtifact(sim_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_sim_unit_tests.step);
}
