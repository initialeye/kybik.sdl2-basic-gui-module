const I = @import("interface-gui.zig");

pub const std = @import("std");
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

pub var textureInitialized = false;
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

const vptr = I.Virtual {
    .create_window = Export.create_window,
    .update_window = Export.update_window,
    .window_widget = Export.window_widget,
    .create_widget = Export.create_widget,
    .set_widget_junction_point = Export.set_widget_junction_point,
    .reset_widget_junction_point = Export.reset_widget_junction_point,
    .set_widget_property_str = Export.set_widget_property_str,
    .set_widget_property_int = Export.set_widget_property_int,
    .set_widget_property_flt = Export.set_widget_property_flt,
    .get_widget_property_str = Export.get_widget_property_str,
    .get_widget_property_int = Export.get_widget_property_int,
    .get_widget_property_flt = Export.get_widget_property_flt,
    .load_texture = Export.load_texture,
    .get_texture = Export.get_texture,
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
};

pub fn handle_error(e: Error, src: std.builtin.SourceLocation, optMsg: []const u8) void {
    _ = src;
    switch (e) {
        else => return,
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
    if (textureInitialized) {
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
    fn create_window(title: F.String, x: u16, y: u16) callconv(.C) ?I.WinPtr {
        var res = W.MainWindow.create(title.from(), .{ .x = @intCast(i16, x), .y = @intCast(i16, y), }) catch |e| {
            handle_error(e, @src(), "");
            return null;
        };
        windows.append(allocator, res) catch handle_error(Error.OutOfMemory, @src(), "");
        if (textureInitialized == false) {
            const size = R.Size{ .x = 128, .y = 64, };
            const surf = R.drawButtonTemplate(size) catch |e| {
                handle_error(convert_sdl2_error(e), @src(), "failed to create button background");
                return @ptrCast(I.WinPtr, res);
            };
            defer surf.destroy();
            buttonTemplate = R.Texture.createSurface(res.b.renderer, surf) catch |e| {
                handle_error(convert_sdl2_error(e), @src(), "failed to create button background");
                return @ptrCast(I.WinPtr, res);
            };
            textureInitialized = true;
        }
        return @ptrCast(I.WinPtr, res);
    }
    fn update_window(window: I.WinPtr) callconv(.C) void {
        var w = @ptrCast(*W.MainWindow, window);
        w.run_update_all() catch |e| {
            handle_error(e, @src(), "");
        };
    }
    fn window_widget(winPtr: I.WinPtr) callconv(.C) I.WidPtr {
        var win = @ptrCast(*W.MainWindow, winPtr);
        return @ptrCast(I.WidPtr, &win.widgetInst);
    }
    fn create_widget(parentWidget: I.WidPtr, nameId: F.String) callconv(.C) ?I.WidPtr {
        var pW = @ptrCast(*W.Widget, parentWidget);
        const cW = W.WidgetFactory.create(pW.get_renderer(), nameId.from()) catch |e| {
            handle_error(e, @src(), "");
            return null;
        };
        const res = pW.add_child(cW) catch |e| {
            cW.destroy();
            handle_error(e, @src(), "");
            return null;
        };
        return @ptrCast(I.WidPtr, res);
    }
    fn set_widget_junction_point(wgt: I.WidPtr, parX: i32, parY: i32, chX: i32, chY: i32, idx: u8) callconv(.C) bool {
        if(idx > 1) return false;
        var w = @ptrCast(*W.Widget, wgt);
        var anchor = w.get_anchor();
        anchor.b[idx] = W.Widget.Binding{
            .p = R.IPoint{ .x = @intCast(i16, parX), .y = @intCast(i16, parY), },
            .c = R.IPoint{ .x = @intCast(i16, chX), .y = @intCast(i16, chY), },
        };
        w.set_anchor(anchor);
        return true;
    }
    fn reset_widget_junction_point(wgt: I.WidPtr, idx: u8) callconv(.C) bool {
        if(idx > 1) return false;
        var w = @ptrCast(*W.Widget, wgt);
        const bind = w.get_anchor().b[@intCast(u1, idx) +% 1];
        const anchor = W.Widget.Anchor{ .b = .{ bind, bind } };
        w.set_anchor(anchor);
        return true;
    }
    fn set_widget_property_str(wgt: I.WidPtr, name: F.String, value: F.String) callconv(.C) bool {
        var w = @ptrCast(*W.Widget, wgt);
        return w.set_property_str(name.from(), value.from());
    }
    fn set_widget_property_int(wgt: I.WidPtr, name: F.String, value: i64) callconv(.C) bool {
        var w = @ptrCast(*W.Widget, wgt);
        return w.set_property_int(name.from(), value);
    }
    fn set_widget_property_flt(wgt: I.WidPtr, name: F.String, value: f64) callconv(.C) bool {
        var w = @ptrCast(*W.Widget, wgt);
        return w.set_property_flt(name.from(), value);
    }
    fn get_widget_property_str(wgt: I.WidPtr, name: F.String) callconv(.C) F.String {
        var w = @ptrCast(*W.Widget, wgt);
        return F.String.init(w.get_property_str(name.from()));
    }
    fn get_widget_property_int(wgt: I.WidPtr, name: F.String) callconv(.C) i64 {
        var w = @ptrCast(*W.Widget, wgt);
        return w.get_property_int(name.from());
    }
    fn get_widget_property_flt(wgt: I.WidPtr, name: F.String) callconv(.C) f64 {
        var w = @ptrCast(*W.Widget, wgt);
        return w.get_property_flt(name.from());
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

