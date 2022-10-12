pub const std = @import("std");
pub const I = @import("interface-gui.zig");
pub const F = @import("framework.zig");
pub const W = @import("widget.zig");
pub const R = @import("render.zig");
pub const E = @import("events.zig");

pub const Vector = std.ArrayListUnmanaged;

pub var core: *const F.Core = undefined;
pub var module: F.Module = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var windows: Vector(*W.MainWindow) = .{};
pub var resources: []const u8 = undefined;
pub var textures: R.TextureStorage = .{};
pub var font: R.Font = undefined;

pub var firstWindowCreated = false;
pub var buttonTemplate: R.Texture = undefined;

var mtx: std.Thread.Mutex = .{};

const MODULE_VERSION = F.PatchVersion.init(0, 0);

const HEADER = F.ModuleHeader {
    .name = F.String.init("SDL2 GUI"),
    .desc = F.String.init("SDL2 based GUI implementation"),
    .deps = F.Deps.init(dependencies[0..]),
    .vers = F.Version.init(I.INTERFACE_VERSION, MODULE_VERSION),
    .logp = .{ 'S', 'D', 'L', 'G', 'U', 'I', 0, 0 },
    .dirn = .{ 's', 'd', 'l', '-', 'g', 'u', 'i', 0 },
    .func = F.ModuleFunctions {
        .init = init,
        .quit = quit,
        .run = run,
        .handle = handle,
        .resolve_dependency = resolve_dependency,
    },
    .intf = F.Interface{
        .name = F.String.init("Basic GUI"),
        .desc = F.String.init("GUI contains only neccessary features"),
        .attr = I.ATTRIBUTES,
        .iffn = F.InterfaceFunctions{
            .vptr = @ptrCast(*const F.VPtr, &vptr),
            .len  = 9,
        },
        .get_func_info = I.get_func_info,
    },
};

const dependencies = [0]F.Dependency {};

const vptr = I.ModuleVirtual {
    .create_window = Export.create_window,
    .load_texture = Export.load_texture,
    .get_texture = Export.get_texture,
    .get_texture_count = Export.get_texture_count,
    .get_texture_path = Export.get_texture_path,
    .get_texture_size = Export.get_texture_size,
};

export fn API_version() usize {
    return I.API_VERSION;
}

export fn load() *const F.ModuleHeader {
    return &HEADER;
}

pub const Error = error {
    OutOfMemory,
    RenderFailed,
    WidgetNotFound,
    NoRenderingContext,
    TextureLoadFailed,
    ObjectNotFound,
};

pub fn handle_error(e: Error, src: std.builtin.SourceLocation, optMsg: []const u8) void {
    _ = src;
    switch (e) {
        error.OutOfMemory        => core.log(module, F.LogLevel.Critical, F.String.init("Allocation failed - no memory to use.")),
        error.RenderFailed       => core.log(module, F.LogLevel.Error, F.String.init("Rendering failed.")),
        error.WidgetNotFound     => core.log(module, F.LogLevel.Error, F.String.init("Unable to find widget.")),
        error.NoRenderingContext => core.log(module, F.LogLevel.Error, F.String.init("Trying to use renderer, but no context found.")),
        error.TextureLoadFailed  => core.log(module, F.LogLevel.Error, F.String.init("Texture load failed.")),
        error.ObjectNotFound     => core.log(module, F.LogLevel.Error, F.String.init("Object not found.")),
    }
    _ = optMsg;
}

pub fn convert_sdl2_error(e: R.Error) Error {
    return switch(e) {
        R.Error.InitFailed,
        R.Error.CreateFailed,
        R.Error.RenderFailed,
        R.Error.LoadFailed,
        R.Error.InvalidData => Error.RenderFailed,
    };
}

const funcs = F.Functions {
    .init = init,
    .quit = quit,
    .run = run,
    .handle = handle,
};

fn init(corePtr: *const F.Core, thisPtr: F.Module) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    core = corePtr;
    module = thisPtr;
    var al = core.get_allocator(module);
    allocator = .{
        .ptr = al.ptr,
        .vtable = @ptrCast(*const std.mem.Allocator.VTable, al.vtable),
    };
    R.init();
    resources = core.get_resource_path(module).from();
    var paths = [_][]const u8 { resources, "test.ttf", };
    const fontPath = std.fs.path.joinZ(allocator, paths[0..]) catch {
        handle_error(Error.OutOfMemory, @src(), "");
        return;
    };
    defer allocator.free(fontPath);
    font = R.Font.create(fontPath, 20) catch |e| {
        handle_error(convert_sdl2_error(e), @src(), "");
        return;
    };
}

fn run() callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    core.schedule_task(module, handle_events_task, 10_000_000, F.CbCtx{ .f1 = 0, .f2 = null });
    core.schedule_task(module, update, 30_000_000, F.CbCtx{ .f1 = 0, .f2 = null });
}

fn quit() callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    textures.destroy();
    for (windows.items) |w| {
        w.widgetInst.destroy();
    }
    windows.deinit(allocator);
    if (firstWindowCreated) {
        buttonTemplate.destroy();
    }
    font.destroy();
    R.quit();
}

fn resolve_dependency(mod: *const F.ModuleHeader) callconv(.C) bool {
    _ = mod;
    return true;
}

fn handle(inf: *const F.Interface, evid: u64) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    _ = inf;
    _ = evid;
}

const Export = struct {
    fn create_window(title: F.String, x: u16, y: u16) callconv(.C) I.Widget {
        var res = W.MainWindow.create(title.from(), .{ .x = @intCast(i16, x), .y = @intCast(i16, y), }) catch |e| {
            handle_error(e, @src(), "");
            return @bitCast(I.Widget, I.GenericInterface.zero);
        };
        windows.append(allocator, res) catch handle_error(Error.OutOfMemory, @src(), "");
        if (firstWindowCreated == false) {
            init_after_win_init(res.b.renderer) catch |e| {
                handle_error(convert_sdl2_error(e), @src(), "failed to create button background");
                return res.widgetInst.to_export();
            };
            firstWindowCreated = true;
        }
        return res.widgetInst.to_export();
    }
    fn load_texture(path: F.String) callconv(.C) ?I.Texture {
        if (windows.items.len == 0) {
            handle_error(Error.NoRenderingContext, @src(), "");
            return null;
        }
        const t = textures.load(windows.items[0].b.renderer, path.from()) catch |e| {
            handle_error(e, @src(), "");
            return null;
        };
        return @intToPtr(I.Texture, @bitCast(usize, t));
    }   
    fn get_texture(path: F.String) callconv(.C) ?I.Texture {
        const t = textures.get(path.from()) orelse return null;
        return @intToPtr(I.Texture, @bitCast(usize, t));
    }
    fn get_texture_count() callconv(.C) usize {
        return textures.count();
    }
    fn get_texture_path(index: usize) callconv(.C) F.String {
        return F.String.init(textures.get_index_path(index) orelse "");
    }
    fn get_texture_size(tex: I.Texture) callconv(.C) I.TextureSize {
        const t = @bitCast(R.Texture, @ptrToInt(tex));
        const size = t.getAttributes().size;
        return .{ .x = @intCast(u32, size.x), .y = @intCast(u32, size.y) };
    }
};

fn handle_events_task(ctx: F.CbCtx) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    const startTime = core.nanotime();
    E.handle_all();
    core.schedule_task(module, handle_events_task, startTime + 10_000_000, ctx);
}

fn update(ctx: F.CbCtx) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    _ = ctx;
    const startTime = core.nanotime();
    for (windows.items) |w| {
        w.run_update_all() catch |e| {
            handle_error(e, @src(), "");
        };
    }
    core.schedule_task(module, update, startTime + 30_000_000, ctx);
}

pub fn mouse_clicked(winId: u32, pos: R.IPoint) void {
    for(windows.items) |w| {
        if (w.get_id() == winId) {
            w.widgetInst.handle_mouse_click(pos, w.widgetInst.get_size().toRect());
            break;
        }
    }
}

fn init_after_win_init(r: R.Renderer) R.Error!void {
    const size = R.Size{ .x = 128, .y = 64, };
    const surf = try R.drawButtonTemplate(size);
    defer surf.destroy();
    buttonTemplate = try R.Texture.createSurface(r, surf);
    load_textures();
}

fn load_textures() void {
    core.iterate_files(module, F.String.init("texture"), F.String.init(""), load_textures_cb);
}
fn load_textures_cb(name: F.String, fullpath: F.String) callconv(.C) void {
    _ = fullpath;
    _ = Export.load_texture(name);
}
