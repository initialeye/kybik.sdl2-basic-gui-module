const gui = @import("gui.zig");

const std = gui.std;
const Error = gui.Error;
const I = gui.I;
const F = gui.F;
const R = gui.R;
const E = gui.E;
const Vector = gui.Vector;

const Instance = opaque{};
const IPtr = *align(@alignOf(*Widget.Base)) Instance;

pub const WidgetFactory = struct {

    const CreateFunc = fn(R.Renderer) Error!Widget;
    const CreateMapElement = struct {
        key: []const u8,
        value: CreateFunc,
    };
    const createMap = [_]CreateMapElement{
        .{ .key = "button", .value = Button.create, },
        .{ .key = "toolbox", .value = Toolbox.create, },
    };

    pub fn create(renderer: R.Renderer, nameId: []const u8) Error!Widget {
        //TODO make binary search
        for (createMap) |elem| {
            if (std.mem.eql(u8, elem.key, nameId)) {
                return elem.value(renderer);
            }
        }
        return Error.WidgetNotFound;
    }
};

pub const Widget = struct {

    pub const Virtual = struct {
        create:           fn (IPtr, []const u8) Error!Widget,
        destroy:          fn (IPtr) void,
        convert:          fn (IPtr, I.InterfaceId) I.GenericInterface,
        to_export:        fn (IPtr) I.Widget,
        set_action:       fn (IPtr, []const u8, F.Action) bool,
        set_anchor:       fn (IPtr, Anchor) void,
        get_anchor:       fn (IPtr) Anchor,
        get_size:         fn (IPtr) R.Size,
        get_areas:        fn (IPtr, R.IRect) SrcDstArea,
        get_renderer:     fn (IPtr) R.Renderer,
        set_property_str: fn (IPtr, []const u8, []const u8) bool,
        set_property_int: fn (IPtr, []const u8, i64) bool,
        set_property_flt: fn (IPtr, []const u8, f64) bool,
        get_property_str: fn (IPtr, []const u8) []const u8,
        get_property_int: fn (IPtr, []const u8) i64,
        get_property_flt: fn (IPtr, []const u8) f64,
        update:           fn (IPtr, SrcDstArea) Error!void,
        handle_mouse_click: fn (IPtr, R.IPoint, R.IRect) void,

        fn Funcs(T: anytype) type {
            return struct {
                fn create(inst: IPtr, nameId: []const u8) Error!Widget {
                    var this = @ptrCast(*T, inst);
                    const ret = try WidgetFactory.create(this.b.renderer, nameId);
                    try this.*.b.add_child(ret);
                    return ret;
                }
                fn destroy(inst: IPtr) void {
                    var this = @ptrCast(*T, inst);
                    for (this.b.children.items) |item| {
                        item.destroy();
                    }
                    this.b.children.deinit(gui.allocator);
                    return this.*.destroy();
                }
                fn convert(inst: IPtr, iid: I.InterfaceId) I.GenericInterface {
                    return @ptrCast(*T, inst).convertWidget(iid);
                }
                fn to_export(inst: IPtr) I.Widget {
                    const this = @ptrCast(*T, inst);
                    return .{ .data = @ptrCast(I.WdgPtr, this), .vptr = &T.vwidget, };
                }
                fn set_action(inst: IPtr, name: []const u8, action: F.Action) bool {
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
                fn get_size(inst: IPtr) R.Size {
                    const this = @ptrCast(*T, inst);
                    return this.b.size;
                }
                fn get_areas(inst: IPtr, parArea: R.IRect) SrcDstArea {
                    const this = @ptrCast(*T, inst);
                    return this.b.anchor.get_sd_area(this.b.size.toRect(), parArea);
                }
                fn get_renderer(inst: IPtr) R.Renderer {
                    const this = @ptrCast(*T, inst);
                    return this.b.renderer;
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
                fn update(inst: IPtr, areas: SrcDstArea) Error!void {
                    var this = @ptrCast(*T, inst);
                    const currArea = this.b.renderer.getViewport();
                    try this.update(areas);
                    for (this.b.children.items) |item| {
                        const targAreas = item.get_areas(currArea);
                        this.b.renderer.setViewport(targAreas.dst) catch |e| return gui.convert_sdl2_error(e);
                        try item.update(targAreas);
                    }
                    this.b.renderer.setViewport(currArea) catch |e| return gui.convert_sdl2_error(e);
                    try this.updated();
                }
                fn updated(inst: IPtr) Error!void {
                    var this = @ptrCast(*T, inst);
                    this.updated();
                }
                fn handle_mouse_click(inst: IPtr, pos: R.IPoint, parentArea: R.IRect) void {
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
        fn generate(T: anytype) Virtual {
            const f = Funcs(T);
            return .{
                .create             = f.create,
                .destroy            = f.destroy,
                .convert            = f.convert,
                .to_export          = f.to_export,
                .set_action         = f.set_action,
                .set_anchor         = f.set_anchor,
                .get_anchor         = f.get_anchor,
                .get_size           = f.get_size,
                .get_areas          = f.get_areas,
                .get_renderer       = f.get_renderer,
                .set_property_str   = f.set_property_str,
                .set_property_int   = f.set_property_int,
                .set_property_flt   = f.set_property_flt,
                .get_property_str   = f.get_property_str,
                .get_property_int   = f.get_property_int,
                .get_property_flt   = f.get_property_flt,
                .update             = f.update,
                .handle_mouse_click = f.handle_mouse_click,
            };
        }
    };

    pub const Export = struct {
        fn Funcs(T: anytype) type {
            return struct {
                const funcs = Virtual.Funcs(T);
                fn convert(iwgt: I.WdgPtr, iid: I.InterfaceId) callconv(.C) I.GenericInterface {
                    return funcs.convert(@ptrCast(IPtr, iwgt), iid);
                }
                fn create(iwgt: I.WdgPtr, name: F.String) callconv(.C) I.Widget {
                    const w = funcs.create(@ptrCast(IPtr, iwgt), name.from()) catch |e| {
                        gui.handle_error(e, @src(), "");
                        return @bitCast(I.Widget, I.GenericInterface.zero);
                    };
                    return w.to_export();
                }
                fn destroy(iwgt: I.WdgPtr) callconv(.C) void {
                    funcs.destroy(@ptrCast(IPtr, iwgt));
                }
                fn set_junction_point(iwgt: I.WdgPtr, parX: i32, parY: i32, chX: i32, chY: i32, idx: u8) callconv(.C) bool {
                    if(idx > 1) return false;
                    const i = @ptrCast(IPtr, iwgt);
                    var anchor = funcs.get_anchor(i);
                    anchor.b[idx] = Binding{
                        .p = R.IPoint{ .x = @intCast(i16, parX), .y = @intCast(i16, parY), },
                        .c = R.IPoint{ .x = @intCast(i16, chX), .y = @intCast(i16, chY), },
                    };
                    funcs.set_anchor(i, anchor);
                    return true;
                }
                fn reset_junction_point(iwgt: I.WdgPtr, idx: u8) callconv(.C) bool {
                    if(idx > 1) return false;
                    const i = @ptrCast(IPtr, iwgt);
                    const bind = funcs.get_anchor(i).b[@intCast(u1, idx) +% 1];
                    const anchor = Anchor{ .b = .{ bind, bind } };
                    funcs.set_anchor(i, anchor);
                    return true;
                }
                fn set_property_str(iwgt: I.WdgPtr, name: F.String, value: F.String) callconv(.C) bool {
                    const i = @ptrCast(IPtr, iwgt);
                    return funcs.set_property_str(i, name.from(), value.from());
                }
                fn set_property_int(iwgt: I.WdgPtr, name: F.String, value: i64) callconv(.C) bool {
                    const i = @ptrCast(IPtr, iwgt);
                    return funcs.set_property_int(i, name.from(), value);
                }
                fn set_property_flt(iwgt: I.WdgPtr, name: F.String, value: f64) callconv(.C) bool {
                    const i = @ptrCast(IPtr, iwgt);
                    return funcs.set_property_flt(i, name.from(), value);
                }
                fn get_property_str(iwgt: I.WdgPtr, name: F.String) callconv(.C) F.String {
                    const i = @ptrCast(IPtr, iwgt);
                    const ret = funcs.get_property_str(i, name.from());
                    return F.String.init(ret);
                }
                fn get_property_int(iwgt: I.WdgPtr, name: F.String) callconv(.C) i64 {
                    const i = @ptrCast(IPtr, iwgt);
                    return funcs.get_property_int(i, name.from());
                }
                fn get_property_flt(iwgt: I.WdgPtr, name: F.String) callconv(.C) f64 {
                    const i = @ptrCast(IPtr, iwgt);
                    return funcs.get_property_flt(i, name.from());
                }
                fn get_original() callconv(.C) usize {
                    return @ptrToInt(&T.virtual);
                }
            };
        }
        fn generate(T: anytype) I.WidgetVirtual {
            const exp = Export.Funcs(T);
            return .{
                .create               = exp.create,
                .destroy              = exp.destroy,
                .convert              = exp.convert,
                .set_junction_point   = exp.set_junction_point,
                .reset_junction_point = exp.reset_junction_point,
                .set_property_str     = exp.set_property_str,
                .set_property_int     = exp.set_property_int,
                .set_property_flt     = exp.set_property_flt,
                .get_property_str     = exp.get_property_str,
                .get_property_int     = exp.get_property_int,
                .get_property_flt     = exp.get_property_flt,
                .__original           = exp.get_original,
            };
        }
    };

    pub const Binding = struct {
        p: R.IPoint = .{}, // Position inside parent widget
        c: R.IPoint = .{}, // Position insize current widget
    };

    pub const SrcDstArea = struct {
        src: R.IRect,
        dst: R.IRect,
    };

    pub const Anchor = struct {
        b: [2]Binding = .{ .{}, .{}},

        fn isXStretched(a: Anchor) bool {
            return a.b[0].c.x != a.b[1].c.x;
        }

        fn isYStretched(a: Anchor) bool {
            return a.b[0].c.y != a.b[1].c.y;
        }

        fn get_sd_area(a: Anchor, srcWgt: R.IRect, dstWgt: R.IRect) SrcDstArea {
            var stX: f32 = 1.0;
            var stY: f32 = 1.0;
            if (a.isXStretched())
                stX = @intToFloat(f32, a.b[0].p.x - a.b[1].p.x)/@intToFloat(f32, a.b[0].c.x - a.b[1].c.x);
            if (a.isYStretched())
                stY = @intToFloat(f32, a.b[0].p.y - a.b[1].p.y)/@intToFloat(f32, a.b[0].c.y - a.b[1].c.y);
            const initX = @intToFloat(f32, dstWgt.x) + @intToFloat(f32, a.b[0].p.x) - @intToFloat(f32, a.b[0].c.x)*stX;
            const initY = @intToFloat(f32, dstWgt.y) + @intToFloat(f32, a.b[0].p.y) - @intToFloat(f32, a.b[0].c.y)*stY;
            const targArea = R.IRect{
                .x = @floatToInt(i16, initX),
                .y = @floatToInt(i16, initY),
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
        renderer: R.Renderer = undefined,
        children: ChildVec = .{},
        anchor:   Anchor   = .{},
        size:     R.Size = .{},

        fn add_child(this: *Base, wid: Widget) Error!void {
            const elem = this.*.children.addOne(gui.allocator) catch return Error.OutOfMemory;
            elem.* = wid;
        }
    };

    const VPtr = *const Virtual;

    pub fn destroy(wid: Widget) void {
        return wid.vptr.destroy(wid.inst);
    }
    pub fn to_internal(iwgt: I.Widget) Widget {
        return .{ .inst = @ptrCast(IPtr, iwgt.data), .vptr = @intToPtr(VPtr, iwgt.vptr.__original()), };
    }
    pub fn to_export(wid: Widget) I.Widget {
        return wid.vptr.to_export(wid.inst);
    }
    pub fn add_child(wid: Widget, child: Widget) Error!*Widget {
        return wid.vptr.add_child(wid.inst, child);
    }
    pub fn set_action(wid: Widget, name: []const u8, action: F.Action) bool {
        return wid.vptr.set_action(wid.inst, name, action);
    }
    pub fn set_anchor(wid: Widget, anchor: Anchor) void {
        return wid.vptr.set_anchor(wid.inst, anchor);
    }
    pub fn get_anchor(wid: Widget) Anchor {
        return wid.vptr.get_anchor(wid.inst);
    }
    pub fn get_size(wid: Widget) R.Size {
        return wid.vptr.get_size(wid.inst);
    }
    pub fn get_areas(wid: Widget, parArea: R.IRect) SrcDstArea {
        return wid.vptr.get_areas(wid.inst, parArea);
    }
    pub fn get_renderer(wid: Widget) R.Renderer {
        return wid.vptr.get_renderer(wid.inst);
    }
    pub fn set_property_str(wid: Widget, name: []const u8, value: []const u8) bool {
        return wid.vptr.set_property_str(wid.inst, name, value);
    }
    pub fn set_property_int(wid: Widget, name: []const u8, value: i64) bool {
        return wid.vptr.set_property_int(wid.inst, name, value);
    }
    pub fn set_property_flt(wid: Widget, name: []const u8, value: f64) bool {
        return wid.vptr.set_property_flt(wid.inst, name, value);
    }
    pub fn get_property_str(wid: Widget, name: []const u8) []const u8 {
        return wid.vptr.get_property_str(wid.inst, name);
    }
    pub fn get_property_int(wid: Widget, name: []const u8) i64 {
        return wid.vptr.get_property_int(wid.inst, name);
    }
    pub fn get_property_flt(wid: Widget, name: []const u8) f64 {
        return wid.vptr.get_property_flt(wid.inst, name);
    }
    pub fn update(wid: Widget, areas: Widget.SrcDstArea) Error!void {
        return wid.vptr.update(wid.inst, areas);
    }
    pub fn updated(wid: Widget, rend: R.Renderer) Error!void {
        return wid.vptr.update(wid.inst, rend);
    }
    pub fn handle_mouse_click(wid: Widget, pos: R.IPoint, parentArea: R.IRect) void {
        return wid.vptr.handle_mouse_click(wid.inst, pos, parentArea);
    }

    vptr: VPtr,
    inst: IPtr,
};

pub const MainWindow = struct {
    b: Widget.Base,
    w: R.Window,
    widgetInst: Widget,

    const virtual = Widget.Virtual.generate(MainWindow);
    const vwidget = Widget.Export.generate(MainWindow);
    const vwindow = Export.generate();

    pub fn get_id(this: *MainWindow) u32 {
        return this.w.getId();
    }
    pub fn run_update_all(this: *MainWindow) Error!void {
        const w = this.widgetInst;
        return w.update(undefined);
    }
    pub fn create(title: []const u8, size: R.Size) Error!*MainWindow {
        const w = R.Window.create(title, size, R.Window.Flags{ .opengl = 1, })
            catch |e| return gui.convert_sdl2_error(e);
        var window = gui.allocator.create(MainWindow) catch return Error.OutOfMemory;
        window.* = .{
            .b = .{
                .size = size,
                .renderer = R.Renderer.create(w, .{ .accelerated = 1, }) catch |e| return gui.convert_sdl2_error(e),
            },
            .w = w,
            .widgetInst = .{
                .inst = @ptrCast(IPtr, window),
                .vptr = &virtual,
            },
        };
        return window;
    }
    fn destroy(this: *MainWindow) void {
        this.b.renderer.destroy();
        this.w.destroy();
        gui.allocator.destroy(this);
    }
    fn convertWidget(this: *MainWindow, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Window => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vwindow), },
            else => return I.GenericInterface.zero,
        };
    }
    fn convertWindow(this: *MainWindow, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Widget => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vwidget), },
            else => return I.GenericInterface.zero,
        };
    }
    fn set_action(this: *MainWindow, name: []const u8, action: F.Action) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = action;
        return false;
    }
    fn set_property_str(this: *MainWindow, name: []const u8, value: []const u8) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }
    fn set_property_int(this: *MainWindow, name: []const u8, value: i64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }
    fn set_property_flt(this: *MainWindow, name: []const u8, value: f64) callconv(.Inline) bool {
        _ = this;
        _ = name;
        _ = value;
        return false;
    }
    fn get_property_str(this: *const MainWindow, name: []const u8) callconv(.Inline) []const u8 {
        _ = this;
        _ = name;
        return "";
    }
    fn get_property_int(this: *const MainWindow, name: []const u8) callconv(.Inline) i64 {
        _ = this;
        _ = name;
        return 0;
    }
    fn get_property_flt(this: *const MainWindow, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        return 0.0;
    }
    fn handle_mouse_click(this: *MainWindow, pos: R.IPoint) void {
        _ = this;
        _ = pos;
    }
    fn update(this: *MainWindow, areas: Widget.SrcDstArea) Error!void {
        _ = areas;
        this.b.renderer.clear(.{ .r = 0, .g = 0, .b = 0, .a = 0}) catch |e| return gui.convert_sdl2_error(e);
    }
    fn updated(this: *MainWindow) Error!void {
        this.b.renderer.present();
    }
    const Export = struct {
        const Funcs = struct {
            fn convert(iwgt: I.WinPtr, iid: I.InterfaceId) callconv(.C) I.GenericInterface {
                return MainWindow.convertWindow(@ptrCast(*MainWindow, iwgt), iid);
            }
            fn destroy(iwgt: I.WinPtr) callconv(.C) void {
                MainWindow.destroy(@ptrCast(*MainWindow, iwgt));
            }
        };
        fn generate() I.WindowVirtual {
            return .{
                .convert = Funcs.convert,
                .destroy = Funcs.destroy,
            };
        }
    };
};

const Toolbox = struct {
    b: Widget.Base,

    const virtual = Widget.Virtual.generate(Toolbox);
    const vwidget = Widget.Export.generate(Toolbox);

    fn create(rend: R.Renderer) Error!Widget {
        var toolbox = gui.allocator.create(Toolbox) catch return Error.OutOfMemory;
        toolbox.* = .{
            .b = .{
                .renderer = rend,
                .size = .{ .x = 200, .y = 200, },
            }
        };
        return Widget{ .vptr = &virtual, .inst = @ptrCast(IPtr, toolbox), };
    }
    fn destroy(this: *Toolbox) callconv(.Inline) void {
        gui.allocator.destroy(this);
    }
    fn convertWidget(this: *Toolbox, iid: I.InterfaceId) I.GenericInterface {
        _ = iid;
        _ = this;
        return I.GenericInterface.zero;
    }
    fn set_action(this: *Toolbox, name: []const u8, action: F.Action) callconv(.Inline) bool {
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
    fn update(this: *Toolbox, areas: Widget.SrcDstArea) callconv(.Inline) Error!void {
        _ = areas;
        this.b.renderer.copyFull(gui.buttonTemplate) catch |e| return gui.convert_sdl2_error(e);
    }
    fn updated(this: *Toolbox) callconv(.Inline) Error!void {
        _ = this;
    }
    fn handle_mouse_click(this: *Toolbox, pos: R.IPoint) callconv(.Inline) void {
        _ = this;
        _ = pos;
    }
};

const Button = struct {
    b: Widget.Base,
    label: [:0]const u8 = "",
    actions: Actions,
    texture: R.Texture,

    const Actions = struct {
        click: F.Action = undefined,
    };

    const virtual = Widget.Virtual.generate(Button);
    const vwidget = Widget.Export.generate(Button);

    fn create(rend: R.Renderer) Error!Widget {
        var button = gui.allocator.create(Button) catch return Error.OutOfMemory;
        const size = gui.buttonTemplate.getAttributes().size;
        button.* = .{
            .b = .{
                .renderer = rend,
                .size = size,
            },
            .actions = .{},
            .texture = R.Texture.create(rend, .rgba8888, .target, size) catch |e| return gui.convert_sdl2_error(e),
        };
        try button.draw_button();
        return Widget{ .vptr = &virtual, .inst = @ptrCast(IPtr, button), };
    }
    fn destroy(this: *Button) callconv(.Inline) void {
        if (this.label.len != 0) gui.allocator.free(this.label);
        this.texture.destroy();
        gui.allocator.destroy(this);
    }
    fn convertWidget(this: *Button, iid: I.InterfaceId) I.GenericInterface {
        _ = iid;
        _ = this;
        return I.GenericInterface.zero;
    }
    fn draw_button(this: *Button) Error!void {
        {
            this.*.b.renderer.setTarget(this.*.texture) catch |e| return gui.convert_sdl2_error(e);
            defer this.*.b.renderer.freeTarget() catch unreachable;
            this.*.b.renderer.copyFull(gui.buttonTemplate) catch |e| return gui.convert_sdl2_error(e);
        }
        if (this.label.len != 0) {
            const text = gui.font.renderText(this.label, .{ .r = 255, .g = 255, .b = 255, .a = 255, })
                catch |e| return gui.convert_sdl2_error(e);
            defer text.destroy();
            const texttex = R.Texture.createSurface(this.*.b.renderer, text)
                catch |e| return gui.convert_sdl2_error(e);
            defer texttex.destroy();
            {
                const textsz = texttex.getAttributes().size;
                const inscribed = textsz.toRect().inscribe(this.b.size.toRect().center());
                this.*.b.renderer.setTarget(this.*.texture)
                    catch |e| return gui.convert_sdl2_error(e);
                defer this.*.b.renderer.freeTarget() catch unreachable;
                this.*.b.renderer.copyOriginal(texttex, inscribed) catch |e| return gui.convert_sdl2_error(e);
            }
        }
    }
    fn set_action(this: *Button, name: []const u8, action: F.Action) callconv(.Inline) bool {
        if (std.mem.eql(u8, name, "click")) {
            this.actions.click = action;
            return true;
        }
        return false;
    }
    fn set_property_str(this: *Button, name: []const u8, value: []const u8) callconv(.Inline) bool {
        if (std.mem.eql(u8, name, "label")) {
            if (this.label.len != 0) gui.allocator.free(this.label);
            this.label = gui.allocator.dupeZ(u8, value) catch |e| {
                gui.handle_error(e, @src(), "");
                return false;
            };
            this.draw_button() catch |e| {
                gui.handle_error(e, @src(), "");
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
    fn update(this: *Button, areas: Widget.SrcDstArea) callconv(.Inline) Error!void {
        this.b.renderer.copyPartial(this.texture, areas.src) catch |e| return gui.convert_sdl2_error(e);
        _ = this;
    }
    fn updated(this: *Button) callconv(.Inline) Error!void {
        _ = this;
    }
    fn handle_mouse_click(this: *Button, pos: R.IPoint) callconv(.Inline) void {
        _ = this;
        _ = pos;
    }
};
