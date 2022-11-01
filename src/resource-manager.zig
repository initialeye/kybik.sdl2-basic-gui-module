const std = @import("std");
const gui = @import("gui.zig");
const sdl2 = @import("sdl2.zig");
const image = @import("sdl-image.zig");
const ttf = @import("sdl-ttf.zig");

const I = gui.I;
const F = gui.F;
const R = gui.R;
const ResourceManager = @This();
const Renderer = sdl2.Renderer;
const Surface = sdl2.Surface;
const Texture = sdl2.Texture;
const Font = ttf.Font;

pub const Resource = struct {
    resType: I.ResourceType,
    data: ResourceUnion,

    const ResourceUnion = union {
        texture: Texture,
        surface: Surface,
        font: Font,
    };
    fn destroy(this: *Resource) void {
        switch(this.resType) {
            .Texture => { this.data.texture.destroy(); },
            .Font => { this.data.font.destroy(); },
            else => {},
        }
    }
};

pub const LabeledTexture = struct {
    path: []const u8,
    data: Texture,
};

pub const LabeledFont = struct {
    path: []const u8,
    data: Font,
};

data: std.StringHashMapUnmanaged(Resource) = .{},

pub fn destroy(this: *ResourceManager) void {
    var iter = this.data.iterator();
    while(iter.next()) |entry| {
        gui.allocator.free(entry.key_ptr.*);
        entry.value_ptr.destroy();
    }
    this.data.deinit(gui.allocator);
}

pub fn load_texture(this: *ResourceManager, rend: Renderer, path: []const u8, file: []const u8) gui.Error!LabeledTexture {
    const pathZ = gui.allocator.dupeZ(u8, path) catch return gui.Error.OutOfMemory;
    defer gui.allocator.free(pathZ);

    var v = this.data.getOrPut(gui.allocator, file) catch return gui.Error.OutOfMemory;
    if (!v.found_existing) {
        const tex = image.loadTexture(rend, pathZ) catch return gui.Error.TextureLoadFailed;
        errdefer tex.destroy();
        v.key_ptr.* = gui.allocator.dupeZ(u8, file) catch return gui.Error.OutOfMemory;
        v.value_ptr.* = .{
            .resType = .Texture,
            .data = .{
                .texture = tex,
            },
        };
    } else if (v.value_ptr.resType != I.ResourceType.Texture) {
        return gui.Error.WrongTypeDetected;
    }
    return LabeledTexture{
        .path = v.key_ptr.*,
        .data = v.value_ptr.*.data.texture,
    };
}
pub fn get_texture(this: *ResourceManager, file: []const u8) ?LabeledTexture {
    const e = this.data.getEntry(file) orelse return null;
    if (e.value_ptr.resType != I.ResourceType.Texture) {
        return null;
    }
    return LabeledTexture{ .data = e.value_ptr.*.data.texture, .path = file };
}
pub fn create_font(this: *ResourceManager, path: []const u8, file: []const u8, ftsize: u16) gui.Error!LabeledFont {
    const saved = std.fmt.allocPrint(gui.allocator, "{s}[{}]", .{ file, ftsize, }) catch return gui.Error.OutOfMemory;
    var v = this.data.getOrPut(gui.allocator, saved) catch return gui.Error.OutOfMemory;
    if (!v.found_existing) {
        const fileZ = gui.allocator.dupeZ(u8, path) catch return gui.Error.OutOfMemory;
        defer gui.allocator.free(fileZ);
        const created = R.Font.create(fileZ, ftsize) catch |e| return gui.convert_sdl2_error(e);
        errdefer created.destroy();
        v.key_ptr.* = saved;
        v.value_ptr.* = .{
            .resType = .Font,
            .data = .{
                .font = created,
            },
        };
    } else {
        gui.allocator.free(saved);
        if (v.value_ptr.resType != I.ResourceType.Font) {
            return gui.Error.WrongTypeDetected;
        }
    }
    return LabeledFont{
        .path = v.key_ptr.*,
        .data = v.value_ptr.*.data.font,
    };
}
pub fn get_font(this: *ResourceManager, file: []const u8, ftsize: u16) ?LabeledFont {
    const saved = std.fmt.allocPrint(gui.allocator, "{s}[{}]", .{ file, ftsize, }) catch return null;
    defer gui.allocator.free(saved);
    const e = this.data.getEntry(saved) orelse return null;
    if (e.value_ptr.resType != I.ResourceType.Texture) {
        return null;
    }
    return LabeledFont{ .data = e.value_ptr.*.data.font, .path = file };
}
pub fn count(this: *ResourceManager) usize {
    return this.data.count();
}
