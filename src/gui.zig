const std = @import("std");
const Fw = @import("framework.zig");
const Gui = @import("interface-gui.zig");

pub const Render = @import("render.zig");
pub const Events = @import("events.zig");

const Vector = std.ArrayListUnmanaged;
const Instance = opaque{};
const IPtr = *align(@alignOf(*Widget.Base)) Instance;

pub var core: *const Fw.Core = undefined;
pub var module: Fw.Module = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var windows: Vector(*MainWindow) = .{};
pub var resources: []const u8 = undefined;
pub var textures: Render.TextureStorage = .{};
pub var font: Render.Font = undefined;

pub var textureInitialized = false;
pub var buttonTemplate: Render.Texture = undefined;

var mtx: std.Thread.Mutex = .{};

const MODULE_VERSION = Fw.PatchVersion.init(0, 0);

const HEADER = Fw.ModuleHeader {
    .name = Fw.String.init("SDL2 GUI"),
    .desc = Fw.String.init("SDL2 based GUI implementation"),
    .deps = Fw.Deps.init(dependencies[0..]),
    .vers = Fw.Version.init(Gui.INTERFACE_VERSION, MODULE_VERSION),
    .logp = .{ 'S', 'D', 'L', 'G', 'U', 'I', 0, 0 },
    .dirn = .{ 's', 'd', 'l', '-', 'g', 'u', 'i', 0 },
    .func = Fw.ModuleFunctions {
        .init = init,
        .quit = quit,
        .run = run,
        .handle = handle,
        .resolve_dependency = resolve_dependency,
    },
    .intf = Fw.Interface{
        .name = Fw.String.init("Basic GUI"),
        .desc = Fw.String.init("GUI contains only neccessary features"),
        .attr = Gui.ATTRIBUTES,
        .iffn = Fw.InterfaceFunctions{
            .vptr = @ptrCast(*const Fw.VPtr, &vptr),
            .len  = 9,
        },
        .get_func_info = Gui.get_func_info,
    },
};

const dependencies = [0]Fw.Dependency {};

const vptr = Gui.Virtual {
    .create_window = Export.create_window,
    .update_window = Export.update_window,
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
    return Gui.API_VERSION;
}

export fn load() *const Fw.ModuleHeader {
    return &HEADER;
}

pub const Error = error {
    OutOfMemory,
    RenderFailed,
    WidgetNotFound,
    NoRenderingContext,
    TextureLoadFailed,
};

fn handle_error(e: Error, src: std.builtin.SourceLocation, optMsg: []const u8) void {
    _ = src;
    switch (e) {
        else => return,
    }
    _ = optMsg;
}

fn convert_sdl2_error(e: Render.Error) Error {
    return switch(e) {
        Render.Error.InitFailed,
        Render.Error.CreateFailed,
        Render.Error.RenderFailed,
        Render.Error.LoadFailed,
        Render.Error.InvalidData => Error.RenderFailed,
    };
}

const funcs = Fw.Functions {
    .init = init,
    .quit = quit,
    .run = run,
    .handle = handle,
};

fn init(corePtr: *const Fw.Core, thisPtr: Fw.Module) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    core = corePtr;
    module = thisPtr;
    var al = core.get_allocator(module);
    allocator = .{
        .ptr = al.ptr,
        .vtable = @ptrCast(*const std.mem.Allocator.VTable, al.vtable),
    };
    Render.init();
    resources = core.get_resource_path(module).from();
    var paths = [_][]const u8 { resources, "test.ttf", };
    const fontPath = std.fs.path.joinZ(allocator, paths[0..]) catch {
        handle_error(Error.OutOfMemory, @src(), "");
        return;
    };
    defer allocator.free(fontPath);
    font = Render.Font.create(fontPath, 20) catch |e| {
        handle_error(convert_sdl2_error(e), @src(), "");
        return;
    };
}

fn run() callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    core.schedule_task(module, handle_events_task, 10_000_000, Fw.CbCtx{ .f1 = 0, .f2 = null });
    core.schedule_task(module, update, 30_000_000, Fw.CbCtx{ .f1 = 0, .f2 = null });
}

fn quit() callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    textures.destroy();
    for (windows.items) |w| {
        w.destroy();
    }
    windows.deinit(allocator);
    if (textureInitialized) {
        buttonTemplate.destroy();
    }
    font.destroy();
    Render.quit();
}

fn resolve_dependency(mod: *const Fw.ModuleHeader) callconv(.C) bool {
    _ = mod;
    return true;
}

fn handle(inf: *const Fw.Interface, evid: u64) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    _ = inf;
    _ = evid;
}

const Export = struct {
    fn create_window(title: Fw.String) callconv(.C) ?Gui.WinPtr {
        var res = MainWindow.create(title.from()) catch |e| {
            handle_error(e, @src(), "");
            return null;
        };
        windows.append(allocator, res) catch handle_error(Error.OutOfMemory, @src(), "");
        if (textureInitialized == false) {
            const size = Render.Size{ .x = 128, .y = 64, };
            const surf = Render.drawButtonTemplate(size) catch |e| {
                handle_error(convert_sdl2_error(e), @src(), "failed to create button background");
                return @ptrCast(Gui.WinPtr, res);
            };
            defer surf.destroy();
            buttonTemplate = Render.Texture.createSurface(res.r, surf) catch |e| {
                handle_error(convert_sdl2_error(e), @src(), "failed to create button background");
                return @ptrCast(Gui.WinPtr, res);
            };
            textureInitialized = true;
        }
        return @ptrCast(Gui.WinPtr, res);
    }
    fn update_window(window: Gui.WinPtr) callconv(.C) void {
        var w = @ptrCast(*MainWindow, window);
        w.update() catch |e| {
            handle_error(e, @src(), "");
        };
    }
    fn create_widget(winPtr: Gui.WinPtr, parentWidget: ?Gui.WidPtr, nameId: Fw.String) callconv(.C) ?Gui.WidPtr {
        var win = @ptrCast(*MainWindow, winPtr);
        if (parentWidget != null) {
            const cwgt = WidgetFactory.create(win, nameId.from()) catch |e| {
                handle_error(e, @src(), "");
                return null;
            };
            const pwgt = @ptrCast(*Widget, parentWidget);
            const res = pwgt.add_child(cwgt) catch |e| {
                cwgt.destroy();
                handle_error(e, @src(), "");
                return null;
            };
            return @ptrCast(Gui.WidPtr, res);
        } else {
            const cwgt = WidgetFactory.create(win, nameId.from()) catch |e| {
                handle_error(e, @src(), "");
                return null;
            };
            const res = win.add_child(cwgt) catch |e| {
                cwgt.destroy();
                handle_error(e, @src(), "");
                return null;
            };
            return @ptrCast(Gui.WidPtr, res);
        }
    }
    fn set_widget_junction_point(widget: Gui.WidPtr, parX: i32, parY: i32, chX: i32, chY: i32, idx: u8) callconv(.C) bool {
        if(idx > 1) return false;
        var w = @ptrCast(*Widget, widget);
        var anchor = w.get_anchor();
        anchor.b[idx] = Widget.Binding{
            .p = Render.IPoint{ .x = @intCast(i16, parX), .y = @intCast(i16, parY), },
            .c = Render.IPoint{ .x = @intCast(i16, chX), .y = @intCast(i16, chY), },
        };
        w.set_anchor(anchor);
        return true;
    }
    fn reset_widget_junction_point(widget: Gui.WidPtr, idx: u8) callconv(.C) bool {
        if(idx > 1) return false;
        var w = @ptrCast(*Widget, widget);
        const bind = w.get_anchor().b[@intCast(u1, idx) +% 1];
        const anchor = Widget.Anchor{ .b = .{ bind, bind } };
        w.set_anchor(anchor);
        return true;
    }
    fn set_widget_property_str(widget: Gui.WidPtr, name: Fw.String, value: Fw.String) callconv(.C) bool {
        var w = @ptrCast(*Widget, widget);
        return w.set_property_str(name.from(), value.from());
    }
    fn set_widget_property_int(widget: Gui.WidPtr, name: Fw.String, value: i64) callconv(.C) bool {
        var w = @ptrCast(*Widget, widget);
        return w.set_property_int(name.from(), value);
    }
    fn set_widget_property_flt(widget: Gui.WidPtr, name: Fw.String, value: f64) callconv(.C) bool {
        var w = @ptrCast(*Widget, widget);
        return w.set_property_flt(name.from(), value);
    }
    fn get_widget_property_str(widget: Gui.WidPtr, name: Fw.String) callconv(.C) Fw.String {
        var w = @ptrCast(*Widget, widget);
        return Fw.String.init(w.get_property_str(name.from()));
    }
    fn get_widget_property_int(widget: Gui.WidPtr, name: Fw.String) callconv(.C) i64 {
        var w = @ptrCast(*Widget, widget);
        return w.get_property_int(name.from());
    }
    fn get_widget_property_flt(widget: Gui.WidPtr, name: Fw.String) callconv(.C) f64 {
        var w = @ptrCast(*Widget, widget);
        return w.get_property_flt(name.from());
    }
    fn load_texture(path: Fw.String) callconv(.C) ?Gui.Texture {
        if (windows.items.len == 0) {
            handle_error(Error.NoRenderingContext, @src(), "");
            return null;
        }
        const t = textures.load(windows.items[0].r, path.from()) catch |e| {
            handle_error(e, @src(), "");
            return null;
        };
        return @intToPtr(Gui.Texture, @bitCast(usize, t));
    }
    fn get_texture(path: Fw.String) callconv(.C) ?Gui.Texture {
        const t = textures.get(path.from()) orelse return null;
        return @intToPtr(Gui.Texture, @bitCast(usize, t));
    }
    fn get_texture_size(tex: Gui.Texture) callconv(.C) Gui.TextureSize {
        const t = @bitCast(Render.Texture, @ptrToInt(tex));
        const size = t.getAttributes().size;
        return .{ .x = @intCast(u32, size.x), .y = @intCast(u32, size.y) };
    }
};

fn handle_events_task(ctx: Fw.CbCtx) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    const startTime = core.nanotime();
    Events.handle_all();
    core.schedule_task(module, handle_events_task, startTime + 10_000_000, ctx);
}

fn update(ctx: Fw.CbCtx) callconv(.C) void {
    mtx.lock();
    defer mtx.unlock();
    _ = ctx;
    const startTime = core.nanotime();
    for (windows.items) |w| {
        w.update() catch |e| {
            handle_error(e, @src(), "");
        };
    }
    core.schedule_task(module, update, startTime + 30_000_000, ctx);
}

pub fn mouse_clicked(winId: u32, pos: Render.IPoint) void {
    for(windows.items) |w| {
        if (w.get_id() == winId) {
            w.handle_mouse_click(pos);
            break;
        }
    }
}

pub const WidgetFactory = struct {

    const CreateFunc = fn(Render.Renderer) Error!Widget;
    const CreateMapElement = struct {
        key: []const u8,
        value: CreateFunc,
    };
    const createMap = [_]CreateMapElement{
        .{ .key = "button", .value = Button.create, },
        .{ .key = "toolbox", .value = Toolbox.create, },
    };

    pub fn create(mw: *MainWindow, nameId: []const u8) Error!Widget {
        //TODO make binary search
        for (createMap) |elem| {
            if (std.mem.eql(u8, elem.key, nameId)) {
                return elem.value(mw.r);
            }
        }
        return Error.WidgetNotFound;
    }
};

pub const MainWindow = struct {
    c: Widget.ChildVec,
    w: Render.Window,
    r: Render.Renderer,

    fn create(title: []const u8) Error!*MainWindow {
        const w = Render.Window.create(title, Render.Size{ .x = 640, .y = 480, }, Render.Window.Flags{ .opengl = 1, })
            catch |e| return convert_sdl2_error(e);
        var window = allocator.create(MainWindow) catch return Error.OutOfMemory;
        window.* = .{
            .c = .{},
            .w = w,
            .r = Render.Renderer.create(w, .{ .accelerated = 1, }) catch |e| return convert_sdl2_error(e),
        };
        return window;
    }

    fn destroy(this: *MainWindow) void {
        for (this.c.items) |item| {
            item.destroy();
        }
        this.c.deinit(allocator);
        this.r.destroy();
        this.w.destroy();
        allocator.destroy(this);
    }

    fn add_child(this: *MainWindow, wid: Widget) Error!*Widget {
        const elem = this.*.c.addOne(allocator) catch return Error.OutOfMemory;
        elem.* = wid;
        return elem;
    }

    fn get_id(this: *MainWindow) u32 {
        return this.w.getId();
    }

    fn handle_mouse_click(this: *MainWindow, pos: Render.IPoint) void {
        _ = this;
        _ = pos;
        for (this.c.items) |item| {
            const currArea = this.r.getViewport();
            const areas = item.get_areas(currArea);
            if (pos.inside(areas.dst)) {
                item.handle_mouse_click(pos, areas.dst);
                break;
            }
        }
    }

    fn update(this: *MainWindow) Error!void {
        this.r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 0}) catch |e| return convert_sdl2_error(e);
        const currArea = this.r.getViewport();
        for (this.c.items) |item| {
            const targAreas = item.get_areas(currArea);
            this.r.setViewport(targAreas.dst) catch |e| return convert_sdl2_error(e);
            item.update(this.r, targAreas) catch |e| return e;
        }
        this.r.setViewport(currArea) catch |e| return convert_sdl2_error(e);
        this.r.present();
    }
};

pub const Widget = struct {

    pub const Virtual = struct {
        destroy:          fn (IPtr) void,
        add_child:        fn (IPtr, Widget) Error!*Widget,
        set_action:       fn (IPtr, []const u8, Fw.Action) bool,
        set_anchor:       fn (IPtr, Anchor) void,
        get_anchor:       fn (IPtr) Anchor,
        get_size:         fn (IPtr) Render.Size,
        get_areas:        fn (IPtr, Render.IRect) SrcDstArea,
        set_property_str: fn (IPtr, []const u8, []const u8) bool,
        set_property_int: fn (IPtr, []const u8, i64) bool,
        set_property_flt: fn (IPtr, []const u8, f64) bool,
        get_property_str: fn (IPtr, []const u8) []const u8,
        get_property_int: fn (IPtr, []const u8) i64,
        get_property_flt: fn (IPtr, []const u8) f64,
        update:           fn (IPtr, Render.Renderer, SrcDstArea) Error!void,

        handle_mouse_click: fn (IPtr, Render.IPoint, Render.IRect) void,

        pub fn generate(T: anytype) Virtual {
            return Virtual{
                .destroy          = Widget.Funcs(T).destroy,
                .add_child        = Widget.Funcs(T).add_child,
                .set_action       = Widget.Funcs(T).set_action,
                .set_anchor       = Widget.Funcs(T).set_anchor,
                .get_anchor       = Widget.Funcs(T).get_anchor,
                .get_size         = Widget.Funcs(T).get_size,
                .get_areas        = Widget.Funcs(T).get_areas,
                .set_property_str = Widget.Funcs(T).set_property_str,
                .set_property_int = Widget.Funcs(T).set_property_int,
                .set_property_flt = Widget.Funcs(T).set_property_flt,
                .get_property_str = Widget.Funcs(T).get_property_str,
                .get_property_int = Widget.Funcs(T).get_property_int,
                .get_property_flt = Widget.Funcs(T).get_property_flt,
                .update           = Widget.Funcs(T).update,
                .handle_mouse_click = Widget.Funcs(T).handle_mouse_click,
            };
        }
    };

    const Binding = struct {
        p: Render.IPoint = .{}, // Position inside parent widget
        c: Render.IPoint = .{}, // Position insize current widget
    };

    const SrcDstArea = struct {
        src: Render.IRect,
        dst: Render.IRect,
    };

    const Anchor = struct {
        b: [2]Binding = .{ .{}, .{}},

        fn isXStretched(a: Anchor) bool {
            return a.b[0].c.x != a.b[1].c.x;
        }

        fn isYStretched(a: Anchor) bool {
            return a.b[0].c.y != a.b[1].c.y;
        }

        fn get_sd_area(a: Anchor, srcWgt: Render.IRect, dstWgt: Render.IRect) SrcDstArea {
            var stX: f32 = 1.0;
            var stY: f32 = 1.0;
            if (a.isXStretched()) stX = @intToFloat(f32, a.b[0].p.x - a.b[1].p.x)/@intToFloat(f32, a.b[0].c.x - a.b[1].c.x);
            if (a.isYStretched()) stY = @intToFloat(f32, a.b[0].p.y - a.b[1].p.y)/@intToFloat(f32, a.b[0].c.y - a.b[1].c.y);
            const initialX = @intToFloat(f32, dstWgt.x) + @intToFloat(f32, a.b[0].p.x) - @intToFloat(f32, a.b[0].c.x)*stX;
            const initialY = @intToFloat(f32, dstWgt.y) + @intToFloat(f32, a.b[0].p.y) - @intToFloat(f32, a.b[0].c.y)*stY;
            const targArea = Render.IRect{
                .x = @floatToInt(i16, initialX),
                .y = @floatToInt(i16, initialY),
                .w = @floatToInt(i16, @intToFloat(f32, srcWgt.w)*stX),
                .h = @floatToInt(i16, @intToFloat(f32, srcWgt.h)*stY),
            };
            const dst = dstWgt.overlay(targArea);
            const src = .{
                .x = srcWgt.x,
                .y = srcWgt.y,
                .w = @floatToInt(i16, @intToFloat(f32, dst.w)/stX),
                .h = @floatToInt(i16, @intToFloat(f32, dst.h)/stY),
            };
            return .{
                .dst = dst,
                .src = src,
            };
        }
    };

    const ChildVec = Vector(Widget);

    const Base = struct {
        renderer: Render.Renderer = undefined,
        children: ChildVec = .{},
        anchor:   Anchor   = .{},
        size:     Render.Size = .{},

        fn add_child(this: *Base, wid: Widget) Error!*Widget {
            const elem = this.*.children.addOne(allocator) catch return Error.OutOfMemory;
            elem.* = wid;
            return elem;
        }
    };

    const VPtr = *const Virtual;

    fn Funcs(T: anytype) type {
        return struct {
            fn destroy(inst: IPtr) void {
                var this = @ptrCast(*T, inst);
                for (this.b.children.items) |item| {
                    item.destroy();
                }
                this.b.children.deinit(allocator);
                return this.*.destroy();
            }
            fn add_child(inst: IPtr, wid: Widget) Error!*Widget {
                var this = @ptrCast(*T, inst);
                return this.*.b.add_child(wid);
            }
            fn set_action(inst: IPtr, name: []const u8, action: Fw.Action) bool {
                var this = @ptrCast(*T, inst);
                return this.set_action(name, action);
            }
            fn set_anchor(inst: IPtr, anchor: Anchor) void {
                const this = @ptrCast(*T, inst);
                this.b.anchor = anchor;
            }
            fn get_anchor(inst: IPtr) Anchor {
                const this = @ptrCast(*T, inst);
                return this.b.anchor;
            }
            fn get_size(inst: IPtr) Render.Size {
                const this = @ptrCast(*T, inst);
                return this.b.size;
            }
            fn get_areas(inst: IPtr, parArea: Render.IRect) SrcDstArea {
                const this = @ptrCast(*T, inst);
                return this.b.anchor.get_sd_area(this.b.size.toRect(), parArea);
            }
            fn set_property_str(inst: IPtr, name: []const u8, value: []const u8) bool {
                var this = @ptrCast(*T, inst);
                return this.set_property_str(name, value);
            }
            fn set_property_int(inst: IPtr, name: []const u8, value: i64) bool {
                var this = @ptrCast(*T, inst);
                return this.set_property_int(name, value);
            }
            fn set_property_flt(inst: IPtr, name: []const u8, value: f64) bool {
                var this = @ptrCast(*T, inst);
                return this.set_property_flt(name, value);
            }
            fn get_property_str(inst: IPtr, name: []const u8) []const u8 {
                const this = @ptrCast(*T, inst);
                return this.get_property_str(name);
            }
            fn get_property_int(inst: IPtr, name: []const u8) i64 {
                const this = @ptrCast(*T, inst);
                return this.get_property_int(name);
            }
            fn get_property_flt(inst: IPtr, name: []const u8) f64 {
                const this = @ptrCast(*T, inst);
                return this.get_property_flt(name);
            }
            fn update(inst: IPtr, rend: Render.Renderer, areas: SrcDstArea) Error!void {
                var this = @ptrCast(*T, inst);
                const currArea = rend.getViewport();
                try this.update(rend, areas);
                for (this.b.children.items) |item| {
                    const targAreas = item.get_areas(currArea);
                    rend.setViewport(targAreas.dst) catch |e| return convert_sdl2_error(e);
                    try item.update(rend, targAreas);
                }
                rend.setViewport(currArea) catch |e| return convert_sdl2_error(e);
            }
            fn handle_mouse_click(inst: IPtr, pos: Render.IPoint, parentArea: Render.IRect) void {
                var this = @ptrCast(*T, inst);
                for (this.b.children.items) |item| {
                    const areas = item.get_areas(parentArea);
                    if (pos.inside(areas.dst)) {
                        item.handle_mouse_click(pos, areas.dst);
                        break;
                    }
                }
                this.handle_mouse_click(pos);
            }
        };
    }

    fn destroy(wid: Widget) void {
        return wid.vptr.destroy(wid.inst);
    }
    fn add_child(wid: Widget, child: Widget) Error!*Widget {
        return wid.vptr.add_child(wid.inst, child);
    }
    fn set_action(wid: Widget, name: []const u8, action: Fw.Action) bool {
        return wid.vptr.set_action(wid.inst, name, action);
    }
    fn set_anchor(wid: Widget, anchor: Anchor) void {
        return wid.vptr.set_anchor(wid.inst, anchor);
    }
    fn get_anchor(wid: Widget) Anchor {
        return wid.vptr.get_anchor(wid.inst);
    }
    fn get_size(wid: Widget) Render.Size {
        return wid.vptr.get_size(wid.inst);
    }
    fn get_areas(wid: Widget, parArea: Render.IRect) SrcDstArea {
        return wid.vptr.get_areas(wid.inst, parArea);
    }
    fn set_property_str(wid: Widget, name: []const u8, value: []const u8) bool {
        return wid.vptr.set_property_str(wid.inst, name, value);
    }
    fn set_property_int(wid: Widget, name: []const u8, value: i64) bool {
        return wid.vptr.set_property_int(wid.inst, name, value);
    }
    fn set_property_flt(wid: Widget, name: []const u8, value: f64) bool {
        return wid.vptr.set_property_flt(wid.inst, name, value);
    }
    fn get_property_str(wid: Widget, name: []const u8) []const u8 {
        return wid.vptr.get_property_str(wid.inst, name);
    }
    fn get_property_int(wid: Widget, name: []const u8) i64 {
        return wid.vptr.get_property_int(wid.inst, name);
    }
    fn get_property_flt(wid: Widget, name: []const u8) f64 {
        return wid.vptr.get_property_flt(wid.inst, name);
    }
    fn update(wid: Widget, rend: Render.Renderer, areas: Widget.SrcDstArea) Error!void {
        return wid.vptr.update(wid.inst, rend, areas);
    }
    fn handle_mouse_click(wid: Widget, pos: Render.IPoint, parentArea: Render.IRect) void {
        return wid.vptr.handle_mouse_click(wid.inst, pos, parentArea);
    }

    vptr: VPtr,
    inst: IPtr,
};

const Toolbox = struct {
    b: Widget.Base,

    const virtual = Widget.Virtual.generate(Toolbox);

    fn create(rend: Render.Renderer) Error!Widget {
        var toolbox = allocator.create(Toolbox) catch return Error.OutOfMemory;
        toolbox.* = .{
            .b = .{
                .renderer = rend,
                .size = .{ .x = 200, .y = 200, },
            }
        };
        return Widget{ .vptr = &virtual, .inst = @ptrCast(IPtr, toolbox), };
    }

    fn destroy(this: *Toolbox) callconv(.Inline) void {
        allocator.destroy(this);
    }

    fn set_action(this: *Toolbox, name: []const u8, action: Fw.Action) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = action;
        return false;
    }

    fn set_property_str(this: *Toolbox, name: []const u8, value: []const u8) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }

    fn set_property_int(this: *Toolbox, name: []const u8, value: i64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }

    fn set_property_flt(this: *Toolbox, name: []const u8, value: f64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }

    fn get_property_str(this: *const Toolbox, name: []const u8) callconv(.Inline) []const u8 {
        _ = this;
        _ = name;
        return "";
    }

    fn get_property_int(this: *const Toolbox, name: []const u8) callconv(.Inline) i64 {
        _ = this;
        _ = name;
        return 0;
    }

    fn get_property_flt(this: *const Toolbox, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        return 0.0;
    }

    fn update(this: *Toolbox, rend: Render.Renderer, areas: Widget.SrcDstArea) callconv(.Inline) Error!void {
        _ = this;
        _ = rend;
        _ = areas;
        rend.copyFull(buttonTemplate) catch |e| return convert_sdl2_error(e);
    }

    fn handle_mouse_click(this: *Toolbox, pos: Render.IPoint) callconv(.Inline) void {
        _ = this;
        _ = pos;
    }
};

const Button = struct {
    b: Widget.Base,
    label: [:0]const u8 = "",
    actions: Actions,
    texture: Render.Texture,

    const Actions = struct {
        click: Fw.Action = undefined,
    };

    const virtual = Widget.Virtual.generate(Button);

    fn create(rend: Render.Renderer) Error!Widget {
        var button = allocator.create(Button) catch return Error.OutOfMemory;
        const size = buttonTemplate.getAttributes().size;
        button.* = .{
            .b = .{
                .renderer = rend,
                .size = size,
            },
            .actions = .{},
            .texture = Render.Texture.create(rend, .rgba8888, .target, size) catch |e| return convert_sdl2_error(e),
        };
        try button.draw_button();
        return Widget{ .vptr = &virtual, .inst = @ptrCast(IPtr, button), };
    }

    fn destroy(this: *Button) callconv(.Inline) void {
        if (this.label.len != 0) allocator.free(this.label);
        this.texture.destroy();
        allocator.destroy(this);
    }

    fn draw_button(this: *Button) Error!void {
        {
            this.*.b.renderer.setTarget(this.*.texture) catch |e| return convert_sdl2_error(e);
            defer this.*.b.renderer.freeTarget() catch unreachable;
            this.*.b.renderer.copyFull(buttonTemplate) catch |e| return convert_sdl2_error(e);
        }
        if (this.label.len != 0) {
            const text = font.renderText(this.label, .{ .r = 255, .g = 255, .b = 255, .a = 255, })
                catch |e| return convert_sdl2_error(e);
            defer text.destroy();
            const texttex = Render.Texture.createSurface(this.*.b.renderer, text)
                catch |e| return convert_sdl2_error(e);
            defer texttex.destroy();
            {
                const textsz = texttex.getAttributes().size;
                const inscribed = textsz.toRect().inscribe(this.b.size.toRect().center());
                this.*.b.renderer.setTarget(this.*.texture)
                    catch |e| return convert_sdl2_error(e);
                defer this.*.b.renderer.freeTarget() catch unreachable;
                this.*.b.renderer.copyOriginal(texttex, inscribed) catch |e| return convert_sdl2_error(e);
            }
        }
    }

    fn set_action(this: *Button, name: []const u8, action: Fw.Action) callconv(.Inline) bool {
        if (std.mem.eql(u8, name, "click")) {
            this.actions.click = action;
            return true;
        }
        return false;
    }

    fn set_property_str(this: *Button, name: []const u8, value: []const u8) callconv(.Inline) bool {
        if (std.mem.eql(u8, name, "label")) {
            if (this.label.len != 0) allocator.free(this.label);
            this.label = allocator.dupeZ(u8, value) catch |e| {
                handle_error(e, @src(), "");
                return false;
            };
            this.draw_button() catch |e| {
                handle_error(e, @src(), "");
                return false;
            };
            return true;
        }
        return false;
    }

    fn set_property_int(this: *Button, name: []const u8, value: i64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }

    fn set_property_flt(this: *Button, name: []const u8, value: f64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }

    fn get_property_str(this: *const Button, name: []const u8) callconv(.Inline) []const u8 {
        if (std.mem.eql(u8, name, "label")) {
            return this.label;
        }
        return "";
    }

    fn get_property_int(this: *const Button, name: []const u8) callconv(.Inline) i64 {
        _ = this;
        _ = name;
        return 0;
    }

    fn get_property_flt(this: *const Button, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        return 0.0;
    }

    fn update(this: *Button, rend: Render.Renderer, areas: Widget.SrcDstArea) callconv(.Inline) Error!void {
        rend.copyPartial(this.texture, areas.src) catch |e| return convert_sdl2_error(e);
        _ = this;
    }

    fn handle_mouse_click(this: *Button, pos: Render.IPoint) callconv(.Inline) void {
        _ = this;
        _ = pos;
    }
};
