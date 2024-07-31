const build_options = @import("build_options");
const builtin = @import("builtin");

pub usingnamespace @cImport({
    @cInclude("glad/glad.h");
    //if (builtin.os.tag == .windows)
    //    @cInclude("SDL.h")
    //else
    //    @cInclude("SDL2/SDL.h");
    ////@cInclude("minimp3_ex.h");
});
