const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;
const game_lib = @import("game.zig");
const Game = game_lib.Game;
const Display = @import("renderer.zig").Display;
const SCREEN_SIZE = @import("renderer.zig").SCREEN_SIZE;
const HOTRELOAD = build_options.hotreload;
const LIB_SRC_DIR = "zig-out/lib";
const LIB_DEST_DIR = "hotreload_libs";
const LIB_WATCH_PATH = if (is_windows) "zig-out\\lib" else "zig-out/lib";
const SRC_WATCH_PATH = "src";
const Inputs = @import("inputs.zig").Inputs;
const CopyFile = struct { src: []const u8, dst: []const u8 };
const ztracy = @import("ztracy");
// FILES_TO_COPY[0] should be the dll/dylib/whatever.
const FILES_TO_COPY = if (is_windows) [_]CopyFile{
    .{ .src = LIB_SRC_DIR ++ "/forestorio.dll", .dst = LIB_DEST_DIR ++ "/forestorio.dll" },
    .{ .src = LIB_SRC_DIR ++ "/forestorio.lib", .dst = LIB_DEST_DIR ++ "/forestorio.lib" },
    .{ .src = LIB_SRC_DIR ++ "/forestorio.pdb", .dst = LIB_DEST_DIR ++ "/forestorio.pdb" },
} else [_]CopyFile{
    .{ .src = LIB_SRC_DIR ++ "/libforestorio.dylib", .dst = LIB_DEST_DIR ++ "/libforestorio.dylib" },
};
const CMD_PATH = "cmd.exe";
const SCRIPT_PATH = if (is_windows) "hotreload.bat" else "hotreload.sh";
const PLAY_SOUND_ON_SUCCESS = true;
// global variables for hotreloading.
const gameUpdateFrameDynamic_t = @TypeOf(game_lib.gameUpdateFrameDynamic);
var gameUpdateFrameDynamic: *const gameUpdateFrameDynamic_t = game_lib.gameUpdateFrameDynamic;
const gamePresentFrameDynamic_t = @TypeOf(game_lib.gamePresentFrameDynamic);
var gamePresentFrameDynamic: *const gamePresentFrameDynamic_t = game_lib.gamePresentFrameDynamic;
var dll_file: if (HOTRELOAD) std.DynLib else void = undefined;
var dll_change_detected: if (HOTRELOAD) bool else void = undefined;
var src_change_detected: if (HOTRELOAD) bool else void = undefined;
var dll_watcher_thread: if (HOTRELOAD) std.Thread else void = undefined;
var src_watcher_thread: if (HOTRELOAD) std.Thread else void = undefined;
var sound_thread: if (HOTRELOAD) std.Thread else void = undefined;

const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const sgapp = sokol.app_gfx_glue;
const BUILDER_MODE = build_options.builder_mode;
const PLATFORM_LAYER = build_options.platform_layer;
const Event = switch (PLATFORM_LAYER) {
    .sokol => sapp.Event,
    //.sdl => c.SDL_Event,
};

const TICK_RENDER_RATE = 7;
const MAX_UPDATES_PER_FRAME = 10;

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event_cb,
        .width = @intFromFloat(SCREEN_SIZE.x),
        .height = @intFromFloat(SCREEN_SIZE.y),
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "Antbotics",
        .logger = .{ .func = slog.func },
    });
}

var game: Game = undefined;
var inputs: Inputs = .{};
var gpa: std.heap.GeneralPurposeAllocator(.{ .safety = true }) = undefined;
var display: Display = undefined;
var start: i64 = undefined;
var frame_allocator: std.heap.ArenaAllocator = undefined;
var event_buffer: std.ArrayList(Event) = undefined;

export fn init() void {
    sg.setup(.{
        // TODO (31 May 2024 sam):  Put the correct sizes here.
        .buffer_pool_size = 16,
        .image_pool_size = 16,
        .shader_pool_size = 16,
        .pipeline_pool_size = 16,
        .attachments_pool_size = 16,
        //.context = sgapp.context(),
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    var loading_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer loading_arena.deinit();
    display = Display.init(gpa.allocator(), loading_arena.allocator(), "Forestorio") catch unreachable;
    game = Game.init(gpa.allocator(), loading_arena.allocator(), display.viewport) catch unreachable;
    game.renderer.chars = &display.chars;
    if (HOTRELOAD) {
        // clear libs dir - delete it, and recreate
        std.fs.Dir.deleteTree(std.fs.cwd(), LIB_DEST_DIR) catch unreachable;
        std.fs.Dir.makeDir(std.fs.cwd(), LIB_DEST_DIR) catch unreachable;
        reloadLibrary(false) catch unreachable;
        dll_change_detected = false;
        src_change_detected = false;
        spawnDllWatcher();
        spawnRecompileWatcher();
    }
    start = std.time.milliTimestamp();
    frame_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    event_buffer = std.ArrayList(Event).init(gpa.allocator());
}

export fn frame() void {
    // Start the main loop
    const tracy_zone = ztracy.Zone(@src());
    defer tracy_zone.End();
    if (HOTRELOAD and src_change_detected) {
        recompile(frame_allocator.allocator()) catch unreachable;
        src_change_detected = false;
        spawnRecompileWatcher();
    }
    if (HOTRELOAD and dll_change_detected) {
        reloadLibrary(true) catch unreachable;
        dll_change_detected = false;
        game.renderer.chars = &display.chars;
        game.reload = true;
        spawnDllWatcher();
    }
    if (inputs.quit or game.should_quit) {
        sapp.quit();
        return;
    }
    const now = std.time.milliTimestamp();
    const ticks = @as(u64, @intCast(now - start));
    _ = frame_allocator.reset(.retain_capacity);
    for (event_buffer.items) |e| inputs.handleInputs(e, ticks);
    event_buffer.clearRetainingCapacity();
    if (HOTRELOAD and inputs.getKey(.R).is_clicked) game.reload = true;
    gameUpdateFrameDynamic(
        &game,
        ticks,
        @as(*anyopaque, @constCast(&display.viewport)),
        @as(*anyopaque, @constCast(&frame_allocator.allocator())),
        @as(*anyopaque, @constCast(&inputs)),
    );
    gamePresentFrameDynamic(&game);
    display.displayRenderer(ticks, game.renderer);
    inputs.reset();
}

export fn event_cb(e: [*c]const sapp.Event) void {
    event_buffer.append(e.*) catch unreachable;
}

export fn cleanup() void {
    frame_allocator.deinit();
    event_buffer.deinit();
    game.deinit();
    display.deinit();
    _ = gpa.deinit();
    // TODO (06 Dec 2023 sam): cleanup sg and sapp
}

fn recompile(allocator: std.mem.Allocator) !void {
    std.debug.print("recompiling...\t\t", .{});
    const command: []const []const u8 = if (is_windows) &[1][]const u8{SCRIPT_PATH} else &[2][]const u8{ "bash", SCRIPT_PATH };
    var process = std.ChildProcess.init(command, allocator);
    process.cwd_dir = std.fs.cwd();
    _ = try process.spawnAndWait();
}

/// Move library from zig-out to libs folder
/// When first loading, run with close_dll = false. On hotreload, close_dll = true
fn reloadLibrary(close_dll: bool) !void {
    if (!HOTRELOAD) @compileError("reloadLibrary is only meant to be used in hotreload scenario");
    if (close_dll) dll_file.close();
    // TODO (21 Sep 2023 sam): Check if this works with remedybg. otherwise we might have to point
    // build.zig to libs, and do things that way.
    for (FILES_TO_COPY) |paths| try std.fs.Dir.copyFile(std.fs.cwd(), paths.src, std.fs.cwd(), paths.dst, .{});
    const out_path = FILES_TO_COPY[0].dst;
    dll_file = try std.DynLib.open(out_path);
    std.debug.print("reloaded dll: {s}\n", .{out_path});
    gameUpdateFrameDynamic = dll_file.lookup(*gameUpdateFrameDynamic_t, "gameUpdateFrameDynamic").?;
    gamePresentFrameDynamic = dll_file.lookup(*gamePresentFrameDynamic_t, "gamePresentFrameDynamic").?;
    // play sound on succesful hotreload completion.
    if (PLAY_SOUND_ON_SUCCESS) {
        spawnSuccessSoundThread();
    }
}

fn playSuccessSound() void {
    if (!HOTRELOAD) @compileError("playSuccessSound is only meant to be used in hotreload scenario");
    const command: []const []const u8 = &[2][]const u8{ "playsound", "local\\audio\\compile_success.mp3" };
    var process = std.ChildProcess.init(command, std.heap.page_allocator);
    process.cwd_dir = std.fs.cwd();
    _ = process.spawnAndWait() catch unreachable;
}

fn spawnSuccessSoundThread() void {
    if (!HOTRELOAD) @compileError("spawnSuccessSoundThread is only meant to be used in hotreload scenario");
    sound_thread = std.Thread.spawn(.{}, playSuccessSound, .{}) catch unreachable;
    sound_thread.detach();
}

fn spawnDllWatcher() void {
    if (!HOTRELOAD) @compileError("spawnDllWatcher is only meant to be used in hotreload scenario");
    dll_watcher_thread = std.Thread.spawn(.{}, dllWatcher, .{}) catch unreachable;
    // TODO (28 Sep 2023 sam): I am not fully sure who cleans up this memory?
    // Specifically when we quit, I don't know if the thread gets killed.
    dll_watcher_thread.detach();
}

fn spawnRecompileWatcher() void {
    if (!HOTRELOAD) @compileError("spawnRecompileWatcher is only meant to be used in hotreload scenario");
    src_watcher_thread = std.Thread.spawn(.{}, recompileWatcher, .{}) catch unreachable;
    // TODO (28 Sep 2023 sam): I am not fully sure who cleans up this memory?
    // Specifically when we quit, I don't know if the thread gets killed.
    src_watcher_thread.detach();
}

/// Synchronously wait for the LIB_WATCH_PATH to have any changes. Then set the `dll_change_detected` flag
/// to true, so that the game can reload the library.
fn dllWatcher() void {
    if (!HOTRELOAD) @compileError("dllWatcher is only meant to be used in hotreload scenario");
    waitForChangeBlocking(LIB_WATCH_PATH);
    dll_change_detected = true;
}

fn recompileWatcher() void {
    if (!HOTRELOAD) @compileError("recompileWatcher is only meant to be used in hotreload scenario");
    waitForChangeBlocking(SRC_WATCH_PATH);
    src_change_detected = true;
}

/// Uses the system apis to create a blocking call that only returns
/// when there has been some change in the dir at path
fn waitForChangeBlocking(path: []const u8) void {
    if (is_windows) {
        var dirname_path_space: std.os.windows.PathSpace = undefined;
        dirname_path_space.len = std.unicode.utf8ToUtf16Le(&dirname_path_space.data, path) catch unreachable;
        dirname_path_space.data[dirname_path_space.len] = 0;
        const dir_handle = std.os.windows.OpenFile(dirname_path_space.span(), .{
            .dir = std.fs.cwd().fd,
            .access_mask = std.os.windows.GENERIC_READ,
            .creation = std.os.windows.FILE_OPEN,
            //.io_mode = .blocking,
            .filter = .dir_only,
            .follow_symlinks = false,
        }) catch |err| {
            std.debug.print("Error in opening file: {any}\n", .{err});
            unreachable;
        };
        var event_buf: [4096]u8 align(@alignOf(std.os.windows.FILE_NOTIFY_INFORMATION)) = undefined;
        var num_bytes: u32 = 0;
        // The ReadDirectoryChangesW is synchronous. So the thread will wait for the completion of
        // this line until there has been a change before continuing (which in this case is to return).
        _ = std.os.windows.kernel32.ReadDirectoryChangesW(
            dir_handle,
            &event_buf,
            event_buf.len,
            std.os.windows.FALSE, // watch subtree
            std.os.windows.FILE_NOTIFY_CHANGE_FILE_NAME | std.os.windows.FILE_NOTIFY_CHANGE_DIR_NAME |
                std.os.windows.FILE_NOTIFY_CHANGE_ATTRIBUTES | std.os.windows.FILE_NOTIFY_CHANGE_SIZE |
                std.os.windows.FILE_NOTIFY_CHANGE_LAST_WRITE | std.os.windows.FILE_NOTIFY_CHANGE_LAST_ACCESS |
                std.os.windows.FILE_NOTIFY_CHANGE_CREATION | std.os.windows.FILE_NOTIFY_CHANGE_SECURITY,
            &num_bytes, // number of bytes transferred (unused for async)
            null,
            null, // completion routine - unused because we use IOCP
        );
    } else {
        // kevent stuff. Only tested on my mac
        const flags = std.posix.O.SYMLINK | std.posix.O.EVTONLY;
        const fd = std.os.open(path, flags, 0) catch unreachable;
        // create kqueue and kevent
        const kq = std.os.kqueue() catch unreachable;
        var kevs = [1]std.os.Kevent{undefined};
        kevs[0] = std.os.Kevent{
            .ident = @as(usize, @intCast(fd)),
            .filter = std.c.EVFILT_VNODE,
            .flags = std.c.EV_ADD | std.c.EV_ENABLE | std.c.EV_ONESHOT,
            .fflags = std.c.NOTE_WRITE,
            .data = 0,
            .udata = undefined,
        };
        var kev_response = [1]std.os.Kevent{undefined};
        const empty_kevs = &[0]std.os.Kevent{};
        // add kevent to kqueue
        _ = std.os.kevent(kq, &kevs, empty_kevs, null) catch unreachable;
        // wait for kqueue to send back message.
        _ = std.os.kevent(kq, empty_kevs, &kev_response, null) catch unreachable;
        // TODO (19 Oct 2023 sam): How to close kqueue?
    }
}
