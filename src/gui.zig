pub const std = @import("std");
pub const I = @import("interface-gui.zig");
pub const F = @import("framework.zig");
pub const W = @import("widget.zig");
pub const R = @import("render.zig");
pub const E = @import("events.zig");
pub const ResourceManager = @import("resource-manager.zig");

pub const Vector = std.ArrayListUnmanaged;

pub var core: *const F.Core = undefined;
pub var module: F.Module = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var windows: Vector(*W.MainWindow) = .{};
pub var resources: ResourceManager = .{};

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
    .load_textures = Export.load_textures,
    .load_fonts = Export.load_fonts,
    .get_texture = Export.get_texture,
    .get_font = Export.get_font,
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
    WrongTypeDetected,
    InvalidIndexAccess,
    InvalidObject,
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
        error.WrongTypeDetected  => core.log(module, F.LogLevel.Error, F.String.init("Object found, but type was wrong.")),
        error.InvalidIndexAccess => core.log(module, F.LogLevel.Error, F.String.init("Invalid index access detected.")),
        error.InvalidObject      => core.log(module, F.LogLevel.Error, F.String.init("Invalid object.")),
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
    resources.destroy();
    for (windows.items) |w| {
        w.widgetInst.destroy();
    }
    windows.deinit(allocator);
    if (firstWindowCreated) {
        buttonTemplate.destroy();
    }
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
    fn load_textures(folder: F.String, pattern: F.String) callconv(.C) u64 {
        var ctx: F.CbCtx = undefined;
        return core.iterate_files(module, folder, pattern, load_textures_cb, ctx);
    }
    fn load_fonts(folder: F.String, pattern: F.String, size: u16) callconv(.C) u64 {
        var ctx: F.CbCtx = .{ .f1 = size, .f2 = null, };
        return core.iterate_files(module, folder, pattern, load_fonts_cb, ctx);
    }
    fn get_texture(path: F.String) callconv(.C) ?I.Texture {
        const t = resources.get_texture(path.from()) orelse return null;
        return @intToPtr(I.Texture, @bitCast(usize, t.data));
    }
    fn get_font(path: F.String, size: u16) callconv(.C) ?I.Font {
        const f = resources.get_font(path.from(), size) orelse return null;
        return @intToPtr(I.Font, @bitCast(usize, f.data));
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
            w.window_mouse_click(pos);
            break;
        }
    }
}
pub fn mouse_moved(winId: u32, pos: R.IPoint, delta: R.IPoint) void {
    _ = pos;
    _ = delta;
    for(windows.items) |w| {
        if (w.get_id() == winId) {
            w.window_mouse_move(pos, delta);
            break;
        }
    }
}
pub fn mouse_wheel(winId: u32, direction: i8) void {
    _ = direction;
    for(windows.items) |w| {
        if (w.get_id() == winId) {
            w.window_mouse_wheel(direction);
            break;
        }
    }
}

fn init_after_win_init(r: R.Renderer) R.Error!void {
    const size = R.Size{ .x = 128, .y = 64, };
    const surf = try R.drawButtonTemplate(size);
    defer surf.destroy();
    buttonTemplate = try R.Texture.createSurface(r, surf);
}

fn load_textures_cb(name: F.String, fullpath: F.String, ctx: F.CbCtx) callconv(.C) void {
    _ = ctx;
    if (windows.items.len == 0) {
        handle_error(Error.NoRenderingContext, @src(), "");
    }
    _ = resources.load_texture(windows.items[0].b.renderer, fullpath.from(), name.from()) catch |e| {
        handle_error(e, @src(), "");
    };
}
fn load_fonts_cb(name: F.String, fullpath: F.String, ctx: F.CbCtx) callconv(.C) void {
    _ = resources.create_font(fullpath.from(), name.from(), @intCast(u16, ctx.f1)) catch |e| {
        handle_error(e, @src(), "");
    };
}
