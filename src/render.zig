const std = @import("std");
const gui = @import("gui.zig");
const Fw = @import("framework.zig");
const sdl2 = @import("sdl2.zig");
const image = @import("sdl-image.zig");
const ttf = @import("sdl-ttf.zig");

pub const Error = sdl2.Error;
pub const Window = sdl2.Window;
pub const Renderer = sdl2.Renderer;
pub const Surface = sdl2.Surface;
pub const Texture = sdl2.Texture;
pub const Size   = sdl2.Size;
pub const IRect  = sdl2.IRect;
pub const FRect  = sdl2.FRect;
pub const IPoint = sdl2.IPoint;
pub const Font   = ttf.Font;

pub fn init() void {
    sdl2.init(sdl2.InitFlags.all()) catch unreachable;
    ttf.init() catch unreachable;
    image.init(image.Flags{ .jpg = 1, .png = 1, .tiff = 1, }) catch unreachable;
}

pub fn quit() void {
    image.quit();
    ttf.quit();
    sdl2.quit();
}

pub const LabeledTexture = struct {
    path: []const u8,
    text: Texture,
};

pub const TextureStorage = struct {
    data: std.StringArrayHashMapUnmanaged(Texture) = .{},

    pub fn destroy(this: *@This()) void {
        var iter = this.data.iterator();
        while(iter.next()) |entry| {
            gui.allocator.free(entry.key_ptr.*);
            entry.value_ptr.destroy();
        }
        this.data.deinit(gui.allocator);
    }
    pub fn load(this: *@This(), rend: Renderer, file: []const u8) gui.Error!Texture {
        var paths = [_][]const u8 { gui.resources, "./texture/", file, };
        var pathsPartial = [_][]const u8 { "./texture/", file, };
        const fullpath = std.fs.path.joinZ(gui.allocator, paths[0..]) catch return gui.Error.OutOfMemory;
        defer gui.allocator.free(fullpath);
        const partpath = std.fs.path.join(gui.allocator, pathsPartial[0..]) catch return gui.Error.OutOfMemory;
        errdefer gui.allocator.free(partpath);

        var v = this.data.getOrPut(gui.allocator, partpath) catch return gui.Error.OutOfMemory;
        if (!v.found_existing) {
            const tex = image.loadTexture(rend, fullpath) catch return gui.Error.TextureLoadFailed;
            errdefer tex.destroy();
            v.value_ptr.* = tex;
        } else {
            gui.allocator.free(partpath);
        }
        return v.value_ptr.*;
    }
    pub fn get(this: *@This(), file: []const u8) ?Texture {
        const e = this.data.getEntry(file) orelse return null;
        return e.value_ptr.*;
    }
    pub fn get_labeled(this: *@This(), file: []const u8) ?LabeledTexture {
        const e = this.data.getEntry(file) orelse return null;
        return LabeledTexture{ .text = e.value_ptr.*, .path = file };
    }
    pub fn count(this: *@This()) usize {
        return this.data.keys().len;
    }
    pub fn get_index_path(this: *@This(), i: usize) ?[]const u8 {
        if (i < this.data.keys().len) {
            const t = this.data.keys();
            const t1 = t[i];
            return t1;
        } else {
            return null;
        }
    }
};

pub fn drawButtonTemplate(size: sdl2.Size) sdl2.Error!sdl2.Surface {
    var surface = try sdl2.Surface.create(sdl2.Surface.Format.rgba8888, size);
    var ctx = try sdl2.Renderer.createDrawContext(surface);
    defer ctx.destroy();
    var vertices: sdl2.Renderer.VerticesC = .{};
    defer vertices.deinit(gui.allocator);
    vertices.setCapacity(gui.allocator, 6) catch unreachable;
    vertices.appendAssumeCapacity(.{
        .pos = sdl2.FPoint{ .x = 0, .y = 0, },
        .color = sdl2.Color{ .r = 127, .g = 0, .b = 0, .a = 255, },
    });
    vertices.appendAssumeCapacity(.{
        .pos = sdl2.FPoint{ .x = @intToFloat(f32, size.x), .y = 0, },
        .color = sdl2.Color{ .r = 127, .g = 0, .b = 127, .a = 255, },
    });
    vertices.appendAssumeCapacity(.{
        .pos = size.toFloat(),
        .color = sdl2.Color{ .r = 0, .g = 127, .b = 127, .a = 255, },
    });
    vertices.appendAssumeCapacity(.{
        .pos = sdl2.FPoint{ .x = 0, .y = 0, },
        .color = sdl2.Color{ .r = 127, .g = 0, .b = 0, .a = 255, },
    });
    vertices.appendAssumeCapacity(.{
        .pos = sdl2.FPoint{ .x = 0, .y = @intToFloat(f32, size.y), },
        .color = sdl2.Color{ .r = 0, .g = 127, .b = 0, .a = 255, },
    });
    vertices.appendAssumeCapacity(.{
        .pos = size.toFloat(),
        .color = sdl2.Color{ .r = 0, .g = 127, .b = 127, .a = 255, },
    });
    try ctx.drawGeometryColor(vertices);
    return surface;
}
