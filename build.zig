const std = @import("std");

const pkgs = struct {
    const kybik = std.build.Pkg{
        .name = "framework.zig",
        .path = std.build.FileSource.relative("./deps/kybik-core/framework.zig"),
    };
    const sdl2 = std.build.Pkg{
        .name = "sdl2.zig",
        .path = std.build.FileSource.relative("./deps/sdl2/sdl2.zig"),
    };
    const sdl_image = std.build.Pkg{
        .name = "sdl-image.zig",
        .path = std.build.FileSource.relative("./deps/sdl2/sdl-image.zig"),
    };
    const sdl_ttf = std.build.Pkg{
        .name = "sdl-ttf.zig",
        .path = std.build.FileSource.relative("./deps/sdl2/sdl-ttf.zig"),
    };
};

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("kybik_basic_gui_sdl2", "src/gui.zig", .unversioned);
    lib.setBuildMode(mode);
    lib.install();
    
    lib.addPackage(pkgs.kybik);
    lib.addPackage(pkgs.sdl2);
    lib.addPackage(pkgs.sdl_image);
    lib.addPackage(pkgs.sdl_ttf);
    lib.linkSystemLibrary("SDL2");
    lib.linkSystemLibrary("SDL2_image");
    lib.linkSystemLibrary("SDL2_ttf");
}
