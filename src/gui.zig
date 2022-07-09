const std = @import("std");
const Fw = @import("framework.zig");
const Gui = @import("interface-gui.zig");
const Render = @import("render.zig");
const Events = @import("events.zig");

const Vector = std.ArrayListUnmanaged;
const Instance = opaque{};
const IPtr = *align(@alignOf(*Widget.Base)) Instance;

pub var core: *const Fw.Core = undefined;
pub var module: Fw.Module = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var windows: Vector(*MainWindow) = .{};
pub var resources: []const u8 = undefined;
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
    .create_window = create_window,
    .update_window = update_window,
    .create_widget = create_widget,
    .set_widget_junction_point = set_widget_junction_point,
    .reset_widget_junction_point = reset_widget_junction_point,
    .set_widget_property_str = set_widget_property_str,
    .set_widget_property_int = set_widget_property_int,
    .set_widget_property_flt = set_widget_property_flt,
    .get_widget_property_str = get_widget_property_str,
    .get_widget_property_int = get_widget_property_int,
    .get_widget_property_flt = get_widget_property_flt,
};

export fn API_version() usize {
    return Gui.API_VERSION;
}

export fn load() *const Fw.ModuleHeader {
    return &HEADER;
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
    const fontPath = std.fs.path.joinZ(allocator, paths[0..]) catch unreachable;
    defer allocator.free(fontPath);
    font = Render.Font.create(fontPath, 20) catch unreachable;
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

fn create_window(title: Fw.String) callconv(.C) Gui.WinPtr {
    var res = MainWindow.create(title.from());
    windows.append(allocator, res) catch unreachable;
    if (textureInitialized == false) {
        const size = Render.Size{ .x = 128, .y = 64, };
        const surf = Render.drawButtonTemplate(size) catch unreachable;
        defer surf.destroy();
        buttonTemplate = Render.Texture.createSurface(res.r, surf) catch unreachable;
    }
    return @ptrCast(Gui.WinPtr, res);
}

fn update_window(window: Gui.WinPtr) callconv(.C) void {
    var w = @ptrCast(*MainWindow, window);
    w.update();
}

fn create_widget(winPtr: Gui.WinPtr, parentWidget: ?Gui.WidPtr, nameId: Fw.String) callconv(.C) ?Gui.WidPtr {
    var win = @ptrCast(*MainWindow, winPtr);
    if (parentWidget != null) {
        const cwgt = WidgetFactory.create(win, nameId.from());
        const pwgt = @ptrCast(*Widget, parentWidget);
        const res = pwgt.vptr.add_child(pwgt.inst, cwgt);
        return @ptrCast(Gui.WidPtr, res);
    } else {
        const cwgt = WidgetFactory.create(win, nameId.from());
        const res = win.add_child(cwgt);
        return @ptrCast(Gui.WidPtr, res);
    }
}

fn set_widget_junction_point(widget: Gui.WidPtr, parX: i32, parY: i32, chX: i32, chY: i32, idx: u8) callconv(.C) bool {
    if(idx > 1) return false;
    var w = @ptrCast(*Widget, widget);
    var anchor = w.vptr.get_anchor(w.inst);
    anchor.b[idx] = Widget.Binding{
        .par = Render.IPoint{ .x = @intCast(i16, parX), .y = @intCast(i16, parY), },
        .cur = Render.IPoint{ .x = @intCast(i16, chX), .y = @intCast(i16, chY), },
    };
    w.vptr.set_anchor(w.inst, anchor);
    return true;
}

fn reset_widget_junction_point(widget: Gui.WidPtr, idx: u8) callconv(.C) bool {
    if(idx > 1) return false;
    var w = @ptrCast(*Widget, widget);
    const bind = w.vptr.get_anchor(w.inst).b[@intCast(u1, idx) +% 1];
    const anchor = Widget.Anchor{ .b = .{ bind, bind } };
    w.vptr.set_anchor(w.inst, anchor);
    return true;
}

fn set_widget_property_str(widget: Gui.WidPtr, name: Fw.String, value: Fw.String) callconv(.C) bool {
    var w = @ptrCast(*Widget, widget);
    return w.vptr.set_property_str(w.inst, name.from(), value.from());
}

fn set_widget_property_int(widget: Gui.WidPtr, name: Fw.String, value: i64) callconv(.C) bool {
    var w = @ptrCast(*Widget, widget);
    return w.vptr.set_property_int(w.inst, name.from(), value);
}

fn set_widget_property_flt(widget: Gui.WidPtr, name: Fw.String, value: f64) callconv(.C) bool {
    var w = @ptrCast(*Widget, widget);
    return w.vptr.set_property_flt(w.inst, name.from(), value);
}

fn get_widget_property_str(widget: Gui.WidPtr, name: Fw.String) callconv(.C) Fw.String {
    var w = @ptrCast(*Widget, widget);
    return Fw.String.init(w.vptr.get_property_str(w.inst, name.from()));
}

fn get_widget_property_int(widget: Gui.WidPtr, name: Fw.String) callconv(.C) i64 {
    var w = @ptrCast(*Widget, widget);
    return w.vptr.get_property_int(w.inst, name.from());
}

fn get_widget_property_flt(widget: Gui.WidPtr, name: Fw.String) callconv(.C) f64 {
    var w = @ptrCast(*Widget, widget);
    return w.vptr.get_property_flt(w.inst, name.from());
}

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
        w.update();
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

    pub fn create(mw: *MainWindow, nameId: []const u8) Widget {
        _ = nameId;
        return Button.create(mw.r);
    }
};

pub const MainWindow = struct {
    c: Widget.ChildVec,
    w: Render.Window,
    r: Render.Renderer,

    fn create(title: []const u8) *MainWindow {
        const w = Render.Window.create(title, Render.Size{ .x = 640, .y = 480, }, Render.Window.Flags{ .opengl = 1, })
            catch unreachable;
        var window = allocator.create(MainWindow) catch unreachable;
        window.* = .{
            .c = .{},
            .w = w,
            .r = Render.Renderer.create(w, .{ .accelerated = 1, }) catch unreachable,
        };
        return window;
    }
    
    fn destroy(this: *MainWindow) void {
        for (this.c.items) |item| {
            item.vptr.destroy(item.inst);
        }
        this.c.deinit(allocator);
        this.r.destroy();
        this.w.destroy();
        allocator.destroy(this);
    }

    fn add_child(this: *MainWindow, wid: Widget) *Widget {
        const elem = this.*.c.addOne(allocator) catch unreachable;
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
            const area = item.vptr.get_area(item.inst);
            if (pos.inside(area)) {
                item.vptr.handle_mouse_click(item.inst, pos);
                break;
            }
        }
    }

    fn update(this: *MainWindow) void {
        this.r.clear(.{ .r = 0, .g = 0, .b = 0, .a = 0}) catch unreachable;
        const currArea = this.r.getViewport();
        for (this.c.items) |item| {
            const targArea = item.vptr.get_area(item.inst);
            this.r.setViewport(targArea) catch unreachable;
            item.vptr.update(item.inst, this.r) catch unreachable;
        }
        this.r.setViewport(currArea) catch unreachable;
        this.r.present();
    }
};

pub const Widget = struct {

    pub const Virtual = struct {
        destroy:          fn (IPtr) void,
        add_child:        fn (IPtr, Widget) *Widget,
        set_action:       fn (IPtr, []const u8, Fw.Action) bool,
        set_anchor:       fn (IPtr, Anchor) void,
        get_anchor:       fn (IPtr) Anchor,
        get_size:         fn (IPtr) Render.Size,
        get_area:         fn (IPtr) Render.IRect,
        set_property_str: fn (IPtr, []const u8, []const u8) bool,
        set_property_int: fn (IPtr, []const u8, i64) bool,
        set_property_flt: fn (IPtr, []const u8, f64) bool,
        get_property_str: fn (IPtr, []const u8) []const u8,
        get_property_int: fn (IPtr, []const u8) i64,
        get_property_flt: fn (IPtr, []const u8) f64,
        update:           fn (IPtr, Render.Renderer) Render.Error!void,

        handle_mouse_click: fn (IPtr, Render.IPoint) void,
        
        pub fn generate(T: anytype) Virtual {
            return Virtual{
                .destroy          = Widget.Funcs(T).destroy,
                .add_child        = Widget.Funcs(T).add_child,
                .set_action       = Widget.Funcs(T).set_action,
                .set_anchor       = Widget.Funcs(T).set_anchor,
                .get_anchor       = Widget.Funcs(T).get_anchor,
                .get_size         = Widget.Funcs(T).get_size,
                .get_area         = Widget.Funcs(T).get_area,
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
        par: Render.IPoint = .{}, // Position inside parent widget
        cur: Render.IPoint = .{}, // Position insize current widget
    };

    const Anchor = struct {
        b: [2]Binding = .{ .{}, .{}},

        fn isSingle(a: Anchor) bool {
            return a.b[0].cur.eql(a.b[1].cur);
        }

        fn isOnlyX(a: Anchor) bool {
            return a.b[0].cur.y == a.b[1].cur.y and a.b[0].cur.x != a.b[1].cur.x;
        }

        fn isOnlyY(a: Anchor) bool {
            return a.b[0].cur.x == a.b[1].cur.x and a.b[0].cur.y != a.b[1].cur.y;
        }

        fn get_destination_area(a: Anchor, src: Render.Size) Render.IRect {
            _ = src;
            if (a.isSingle()) {
                return .{
                    .x = a.b[0].par.x - a.b[0].cur.x,
                    .y = a.b[0].par.y - a.b[0].cur.y,
                    .w = src.x,
                    .h = src.y,
                };
            } else
            if (a.isOnlyX()) {
                const stretch:f32 = @intToFloat(f32, a.b[0].par.x - a.b[1].par.x)/@intToFloat(f32, a.b[0].cur.x - a.b[1].cur.x);
                return .{
                    .x = a.b[0].par.x - @floatToInt(i16, @intToFloat(f32, a.b[0].cur.x)*stretch),
                    .y = a.b[0].par.y - a.b[0].cur.y,
                    .w = @floatToInt(i16, @intToFloat(f32, src.x)*stretch),
                    .h = src.y,
                };
            } else
            if (a.isOnlyY()) {
                const stretch:f32 = @intToFloat(f32, a.b[0].par.y - a.b[1].par.y)/@intToFloat(f32, a.b[0].cur.y - a.b[1].cur.y);
                return .{
                    .x = a.b[0].par.x - a.b[0].cur.x,
                    .y = a.b[0].par.y - @floatToInt(i16, @intToFloat(f32, a.b[0].cur.y)*stretch),
                    .w = src.x,
                    .h = @floatToInt(i16, @intToFloat(f32, src.y)*stretch),
                };
            } else {
                const stX:f32 = @intToFloat(f32, a.b[0].par.x - a.b[1].par.x)/@intToFloat(f32, a.b[0].cur.x - a.b[1].cur.x);
                const stY:f32 = @intToFloat(f32, a.b[0].par.y - a.b[1].par.y)/@intToFloat(f32, a.b[0].cur.y - a.b[1].cur.y);
                return .{
                    .x = a.b[0].par.x - @floatToInt(i16, @intToFloat(f32, a.b[0].cur.x)*stX),
                    .y = a.b[0].par.y - @floatToInt(i16, @intToFloat(f32, a.b[0].cur.y)*stY),
                    .w = @floatToInt(i16, @intToFloat(f32, src.x)*stX),
                    .h = @floatToInt(i16, @intToFloat(f32, src.y)*stY),
                };
            }
        }
    };
    
    const ChildVec = Vector(Widget);

    const Base = struct {
        renderer: Render.Renderer = undefined,
        children: ChildVec = .{},
        anchor:   Anchor   = .{},
        size:     Render.Size = .{},

        fn add_child(this: *Base, wid: Widget) *Widget {
            const elem = this.*.children.addOne(allocator) catch unreachable;
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
                    item.vptr.destroy(item.inst);
                }
                this.b.children.deinit(allocator);
                return this.*.destroy();
            }
            fn add_child(inst: IPtr, wid: Widget) *Widget {
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
            fn get_area(inst: IPtr) Render.IRect {
                const this = @ptrCast(*T, inst);
                return this.b.anchor.get_destination_area(this.b.size);
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
            fn update(inst: IPtr, rend: Render.Renderer) Render.Error!void {
                var this = @ptrCast(*T, inst);
                const currSize = this.b.size;
                const currArea = rend.getViewport();
                try this.update(rend);
                for (this.b.children.items) |item| {
                    const targArea = item.vptr.get_anchor(item.inst).get_destination_area(currSize);
                    try rend.setViewport(targArea);
                    item.vptr.update(item.inst, rend) catch unreachable;
                }
                try rend.setViewport(currArea);
            }
            fn handle_mouse_click(inst: IPtr, pos: Render.IPoint) void {
                var this = @ptrCast(*T, inst);
                this.handle_mouse_click(pos);
            }
        };
    }

    vptr: VPtr,
    inst: IPtr,
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

    fn create(rend: Render.Renderer) Widget {
        var button = allocator.create(Button) catch unreachable;
        const size = buttonTemplate.getAttributes().size;
        button.* = .{
            .b = .{
                .renderer = rend,
                .size = size,
            },
            .actions = .{},
            .texture = Render.Texture.create(rend, .rgba8888, .target, size) catch unreachable,
        };
        button.draw_button();
        return .{ .vptr = &virtual, .inst = @ptrCast(IPtr, button), };
    }
    
    fn destroy(this: *Button) void {
        if (this.label.len != 0) allocator.free(this.label);
        this.texture.destroy();
        allocator.destroy(this);
    }
    
    fn draw_button(this: *Button) void {
        {
            this.*.b.renderer.setTarget(this.*.texture) catch unreachable;
            defer this.*.b.renderer.freeTarget() catch unreachable;
            this.*.b.renderer.copyFull(buttonTemplate) catch unreachable;
        }
        if (this.label.len != 0) {
            const text = font.renderText(this.label, .{ .r = 255, .g = 255, .b = 255, .a = 255, }) catch unreachable;
            defer text.destroy();
            const texttex = Render.Texture.createSurface(this.*.b.renderer, text) catch unreachable;
            defer texttex.destroy();
            {
                const textsz = texttex.getAttributes().size;
                const inscribed = this.b.size.toRect().inscribe(textsz.toRect());
                this.*.b.renderer.setTarget(this.*.texture) catch unreachable;
                defer this.*.b.renderer.freeTarget() catch unreachable;
                this.*.b.renderer.copyOriginal(texttex, inscribed) catch unreachable;
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
            this.label = allocator.dupeZ(u8, value) catch unreachable;
            this.draw_button();
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

    fn update(this: *Button, rend: Render.Renderer) callconv(.Inline) Render.Error!void {
        rend.copyFull(this.texture) catch unreachable;
        _ = this;
    }

    fn handle_mouse_click(this: *Button, pos: Render.IPoint) void {
        _ = this;
        _ = pos;
    }
};
