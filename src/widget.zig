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
        .{ .key = "sandbox", .value = Sandbox.create, },
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
        get_size:         fn (IPtr) R.Size,
        get_borders:      fn (IPtr) Borders,
        get_renderer:     fn (IPtr) R.Renderer,
        set_property_str: fn (IPtr, []const u8, []const u8) bool,
        set_property_int: fn (IPtr, []const u8, i64) bool,
        set_property_flt: fn (IPtr, []const u8, f64) bool,
        get_property_str: fn (IPtr, []const u8) []const u8,
        get_property_int: fn (IPtr, []const u8) i64,
        get_property_flt: fn (IPtr, []const u8) f64,
        update:           fn (IPtr, R.FRect) Error!void,
        handle_mouse_click: fn (IPtr, R.IRect, R.IPoint) void,
        handle_mouse_move:  fn (IPtr, R.IRect, R.IPoint, R.IPoint) void,
        handle_mouse_wheel: fn (IPtr, R.IRect, R.IPoint, i8) void,

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
                    if (@hasDecl(T, "convertWidget")) {
                        return @ptrCast(*T, inst).convertWidget(iid);
                    } else {
                        return I.GenericInterface.zero;
                    }
                }
                fn to_export(inst: IPtr) I.Widget {
                    const this = @ptrCast(*T, inst);
                    return .{ .data = @ptrCast(I.WdgPtr, this), .vptr = &T.vwidget, };
                }
                fn set_action(inst: IPtr, name: []const u8, action: F.Action) bool {
                    var this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "set_action")) {
                        return this.set_action(name, action);
                    } else {
                        return false;
                    }
                }
                fn get_size(inst: IPtr) R.Size {
                    const this = @ptrCast(*T, inst);
                    return this.b.size;
                }
                fn get_borders(inst: IPtr) Borders {
                    const this = @ptrCast(*T, inst);
                    return this.b.borders;
                }
                fn get_renderer(inst: IPtr) R.Renderer {
                    const this = @ptrCast(*T, inst);
                    return this.b.renderer;
                }
                fn set_property_str(inst: IPtr, name: []const u8, value: []const u8) bool {
                    var this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "set_property_str")) {
                        return this.set_property_str(name, value);
                    } else {
                        return false;
                    }
                }
                fn set_property_int(inst: IPtr, name: []const u8, value: i64) bool {
                    var this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "set_property_int")) {
                        return this.set_property_int(name, value);
                    } else {
                        return false;
                    }
                }
                fn set_property_flt(inst: IPtr, name: []const u8, value: f64) bool {
                    var this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "set_property_flt")) {
                        return this.set_property_flt(name, value);
                    } else {
                        return false;
                    }
                }
                fn get_property_str(inst: IPtr, name: []const u8) []const u8 {
                    const this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "get_property_str")) {
                        return this.get_property_str(name);
                    } else {
                        return "";
                    }
                }
                fn get_property_int(inst: IPtr, name: []const u8) i64 {
                    const this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "get_property_int")) {
                        return this.get_property_int(name);
                    } else {
                        return 0;
                    }
                }
                fn get_property_flt(inst: IPtr, name: []const u8) f64 {
                    const this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "get_property_flt")) {
                        return this.get_property_flt(name);
                    } else {
                        return 0.0;
                    }
                }
                fn update(inst: IPtr, curArea: R.FRect) Error!void {
                    var this = @ptrCast(*T, inst);
                    if (@hasDecl(T, "update")) {
                        try this.update(curArea);
                    }
                    for (this.b.children.items) |item| {
                        const targArea = item.get_borders().get_destination_area(curArea);
                        this.b.renderer.setViewport(targArea.convert(R.IRect)) catch |e| return gui.convert_sdl2_error(e);
                        try item.update(targArea);
                    }
                    this.b.renderer.setViewport(curArea.convert(R.IRect)) catch |e| return gui.convert_sdl2_error(e);
                    if (@hasDecl(T, "updated")) {
                        try this.updated();
                    }
                }
                fn handle_mouse_click(inst: IPtr, curArea: R.IRect, pos: R.IPoint) void {
                    var this = @ptrCast(*T, inst);
                    for (this.b.children.items) |item| {
                        const targArea = item.get_borders().get_destination_area(curArea.convert(R.FRect));
                        if (pos.inside(targArea.convert(R.IRect))) {
                            item.handle_mouse_click(targArea.convert(R.IRect), pos);
                            break;
                        }
                    }
                    if (@hasDecl(T, "handle_mouse_click")) {
                        this.handle_mouse_click(pos);
                    }
                }
                fn handle_mouse_move(inst: IPtr, curArea: R.IRect, pos: R.IPoint, delta: R.IPoint) void {
                    var this = @ptrCast(*T, inst);
                    const lastPoint = pos.minus(delta);
                    for (this.b.children.items) |item| {
                        const targArea =
                            item.get_borders().get_destination_area(curArea.convert(R.FRect)).convert(R.IRect);
                        if (pos.inside(targArea) or lastPoint.inside(targArea)) {
                            item.handle_mouse_move(targArea, pos, delta);
                        }
                    }
                    if (@hasDecl(T, "handle_mouse_move")) {
                        this.handle_mouse_move(curArea, pos, delta);
                    }
                    if (@hasDecl(T, "mouse_cursor_entered")) {
                        if (!lastPoint.inside(curArea) and pos.inside(curArea)) {
                            this.mouse_cursor_entered(pos, delta);
                        }
                    }
                    if (@hasDecl(T, "mouse_cursor_leaved")) {
                        if (lastPoint.inside(curArea) and !pos.inside(curArea)) {
                            this.mouse_cursor_leaved(pos, delta);
                        }
                    }
                }
                fn handle_mouse_wheel(inst: IPtr, curArea: R.IRect, pos: R.IPoint, dir: i8) void {
                    var this = @ptrCast(*T, inst);
                    for (this.b.children.items) |item| {
                        const targArea = item.get_borders().get_destination_area(curArea.convert(R.FRect));
                        if (pos.inside(targArea.convert(R.IRect))) {
                            item.handle_mouse_wheel(targArea.convert(R.IRect), pos, dir);
                            break;
                        }
                    }
                    if (@hasDecl(T, "handle_mouse_wheel")) {
                        this.handle_mouse_wheel(curArea, pos, dir);
                    }
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
                .get_size           = f.get_size,
                .get_borders        = f.get_borders,
                .get_renderer       = f.get_renderer,
                .set_property_str   = f.set_property_str,
                .set_property_int   = f.set_property_int,
                .set_property_flt   = f.set_property_flt,
                .get_property_str   = f.get_property_str,
                .get_property_int   = f.get_property_int,
                .get_property_flt   = f.get_property_flt,
                .update             = f.update,
                .handle_mouse_click = f.handle_mouse_click,
                .handle_mouse_move  = f.handle_mouse_move,
                .handle_mouse_wheel = f.handle_mouse_wheel,
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
                    return @ptrToInt(&T.vprivate);
                }
            };
        }
        fn generate(T: anytype) I.WidgetVirtual {
            const exp = Export.Funcs(T);
            return .{
                .create               = exp.create,
                .destroy              = exp.destroy,
                .convert              = exp.convert,
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

    const ChildVec = Vector(Widget);

    const Base = struct {
        renderer: R.Renderer = undefined,
        children: ChildVec = .{},
        borders:  Borders  = .{},
        size:     R.Size = .{},

        fn add_child(this: *Base, wid: Widget) Error!void {
            const elem = this.*.children.addOne(gui.allocator) catch return Error.OutOfMemory;
            elem.* = wid;
        }
        fn set_property_borders(this: *Base, name: []const u8, value: f64) bool {
            if (std.mem.eql(u8, name, "left border")) {
                this.borders.left = @floatCast(f32, value);
                this.borders.update();
                return true;
            }
            if (std.mem.eql(u8, name, "right border")) {
                this.borders.right = @floatCast(f32, value);
                this.borders.update();
                return true;
            }
            if (std.mem.eql(u8, name, "top border")) {
                this.borders.top = @floatCast(f32, value);
                this.borders.update();
                return true;
            }
            if (std.mem.eql(u8, name, "bottom border")) {
                this.borders.bottom = @floatCast(f32, value);
                this.borders.update();
                return true;
            }
            return false;
        }
    };

    const Borders = struct {
        left:   f32 = 0.0,
        right:  f32 = 1.0,
        top:    f32 = 0.0,
        bottom: f32 = 1.0,

        sdX: f32 = undefined,
        sdY: f32 = undefined,
        sdW: f32 = undefined,
        sdH: f32 = undefined,
        ssX: f32 = undefined,
        ssY: f32 = undefined,
        ssW: f32 = undefined,
        ssH: f32 = undefined,

        fn update(this: *Borders) void {
            const min = std.math.min;
            const max = std.math.max;
            {
                const left = min(max(this.left, 0.0), 1.0);
                const right = min(max(this.right, 0.0), 1.0);
                this.sdX = left;
                this.sdW = max(right - left, 0.0);
            }
            {
                const top = min(max(this.top, 0.0), 1.0);
                const bottom = min(max(this.bottom, 0.0), 1.0);
                this.sdY = top;
                this.sdH = max(bottom - top, 0.0);
            }
            {
                const scale: f32 = 1.0/(this.right-this.left);
                this.ssX = min(max(-this.left*scale, 0.0), 1.0);
                this.ssW = 1.0 - min(max((this.right-1.0)*scale, 0.0) + max(-this.left*scale, 0.0), 1.0);
            }
            {
                const scale: f32 = 1.0/(this.bottom-this.top);
                this.ssY = min(max(-this.top*scale, 0.0), 1.0);
                this.ssH = 1.0 - min(max((this.bottom-1.0)*scale, 0.0) + max(-this.top*scale, 0.0), 1.0);
            }
        }
        fn get_destination_area(this: Borders, area: R.FRect) R.FRect {
            return .{
                .x = area.x + this.sdX*area.w,
                .y = area.y + this.sdY*area.h,
                .w = this.sdW*area.w,
                .h = this.sdH*area.h,
            };
        }
        fn get_source_area(this: Borders, source: R.IRect) R.IRect {
            return .{
                .x = source.x + @floatToInt(i16, @round(this.ssX*@intToFloat(f32, source.w))),
                .y = source.y + @floatToInt(i16, @round(this.ssY*@intToFloat(f32, source.h))),
                .w = @floatToInt(i16, @round(this.ssW*@intToFloat(f32, source.w))),
                .h = @floatToInt(i16, @round(this.ssH*@intToFloat(f32, source.h))),
            };
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
    pub fn get_size(wid: Widget) R.Size {
        return wid.vptr.get_size(wid.inst);
    }
    pub fn get_borders(wid: Widget) Borders {
        return wid.vptr.get_borders(wid.inst);
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
    pub fn update(wid: Widget, curArea: R.FRect) Error!void {
        return wid.vptr.update(wid.inst, curArea);
    }
    pub fn handle_mouse_click(wid: Widget, curArea: R.IRect, pos: R.IPoint) void {
        return wid.vptr.handle_mouse_click(wid.inst, curArea, pos);
    }
    pub fn handle_mouse_move(wid: Widget, curArea: R.IRect, pos: R.IPoint, delta: R.IPoint) void {
        return wid.vptr.handle_mouse_move(wid.inst, curArea, pos, delta);
    }
    pub fn handle_mouse_wheel(wid: Widget, curArea: R.IRect, pos: R.IPoint, dir: i8) void {
        return wid.vptr.handle_mouse_wheel(wid.inst, curArea, pos, dir);
    }

    vptr: VPtr,
    inst: IPtr,
};

pub const MainWindow = struct {
    b: Widget.Base,
    w: R.Window,
    widgetInst: Widget,
    latestCursorPos: R.Size = .{},

    const vprivate = Widget.Virtual.generate(MainWindow);
    const vwidget = Widget.Export.generate(MainWindow);
    const vwindow = Export.generate();

    pub fn get_id(this: *MainWindow) u32 {
        return this.w.getId();
    }
    pub fn run_update_all(this: *MainWindow) Error!void {
        const w = this.widgetInst;
        return w.update(this.b.size.toRect().convert(R.FRect));
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
                .vptr = &vprivate,
            },
        };
        return window;
    }
    pub fn window_mouse_click(this: *MainWindow, pos: R.IPoint) void {
        this.widgetInst.handle_mouse_click(this.widgetInst.get_size().toRect(), pos);
    }
    pub fn window_mouse_move(this: *MainWindow, pos: R.IPoint, delta: R.IPoint) void {
        this.latestCursorPos = pos;
        this.widgetInst.handle_mouse_move(this.widgetInst.get_size().toRect(), pos, delta);
    }
    pub fn window_mouse_wheel(this: *MainWindow, dir: i8) void {
        this.widgetInst.handle_mouse_wheel(this.widgetInst.get_size().toRect(), this.latestCursorPos, dir);
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
    fn update(this: *MainWindow, curArea: R.FRect) Error!void {
        _ = curArea;
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

const Sandbox = struct {
    b: Widget.Base,
    mapm: MapMesh = .{},
    uTxs: Vector(gui.ResourceManager.LabeledTexture) = .{},
    objs: Vector(Object) = .{},
    pow: PointOfView = .{},

    const vprivate = Widget.Virtual.generate(@This());
    const vwidget = Widget.Export.generate(@This());
    const vsandbox = Export.generate();

    const MapMesh = struct {
        const Cell = struct {
            texId: u32 = 0,
            height: u16 = 0,
        };
        const CellList = std.MultiArrayList(Cell);

        mesh: CellList = .{},
        w: u32 = 0,
        h: u32 = 0,

        fn create(w: u32, h: u32) gui.Error!MapMesh {
            var ret = MapMesh{
                .w = w,
                .h = h,
                .mesh = .{},
            };
            ret.mesh.resize(gui.allocator, w*h) catch return gui.Error.OutOfMemory;
            var i:usize = 0;
            var total:usize = w*h;
            while (i < total) {
                ret.mesh.set(i, .{});
                i += 1;
            }
            return ret;
        }
        fn destroy(this: *MapMesh) void {
            this.mesh.deinit(gui.allocator);
        }
        fn resize(this: *MapMesh, w: u32, h: u32) gui.Error!void {
            const thisW = this.width();
            const thisH = this.height();
            if (w*h != thisW*thisH) {
                this.mesh.resize(gui.allocator, w*h) catch return gui.Error.OutOfMemory;
            }
            this.w = w;
            this.h = h;
            var i:usize = 0;
            var total:usize = w*h;
            while (i < total) {
                this.mesh.set(i, .{});
                i += 1;
            }
        }
        fn x_right(this: *const MapMesh) i32 {
            return @intCast(i32, this.width()/2);
        }
        fn y_bottom(this: *const MapMesh) i32 {
            return @intCast(i32, this.height()/2);
        }
        fn idx(this: *const MapMesh, x: i32, y: i32) usize {
            return this.width()*@intCast(u32, (y + this.y_bottom())) + @intCast(u32, (x + this.x_right()));
        }
        fn get(this: *const MapMesh, x: i32, y: i32) Cell {
            return this.mesh.get(this.idx(x, y));
        }
        fn set(this: *MapMesh, x: i32, y: i32, c: Cell) void {
            this.mesh.set(this.idx(x, y), c);
        }
        fn set_batch(this: *MapMesh, view: *I.MapView) gui.Error!void {
            if (view.len != this.mesh.len) return gui.Error.InvalidObject;
            var i: usize = 0;
            while (i < this.mesh.len) {
                this.mesh.set(i, .{
                    .texId = view.data[i].modelId,
                    .height = 0,
                });
                i += 1;
            }
        }
        fn width(this: *const MapMesh) u32 {
            return this.w;
        }
        fn height(this: *const MapMesh) u32 {
            return this.h;
        }
    };
    pub const PointOfView = struct {
        posX:   f32 = 0.0,
        posY:   f32 = 0.0,
        deltaX: f32 = 0.0,
        deltaY: f32 = 0.0,
        scale: f32 = 1.0,
    };
    const Object = struct {
        texId: u32,
        state: u32,
        x: f32 = 0.0,
        y: f32 = 0.0,
        z: f32 = 0.0,
    };

    fn create(rend: R.Renderer) Error!Widget {
        var sandbox = gui.allocator.create(Sandbox) catch return Error.OutOfMemory;
        sandbox.* = .{
            .mapm = try MapMesh.create(0, 0),
            .b = .{
                .renderer = rend,
                .size = .{ .x = 64, .y = 64, },
            }
        };
        sandbox.uTxs.append(gui.allocator, .{ .data = gui.buttonTemplate, .path = "template"} ) catch return Error.OutOfMemory;
        return Widget{ .vptr = &vprivate, .inst = @ptrCast(IPtr, sandbox), };
    }
    fn destroy(this: *Sandbox) callconv(.Inline) void {
        this.uTxs.deinit(gui.allocator);
        this.mapm.destroy();
        gui.allocator.destroy(this);
    }
    fn convertWidget(this: *Sandbox, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Sandbox => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vsandbox), },
            else => return I.GenericInterface.zero,
        };
    }
    fn convertSandbox(this: *Sandbox, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Widget => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vwidget), },
            else => return I.GenericInterface.zero,
        };
    }
    fn set_property_flt(this: *Sandbox, name: []const u8, value: f64) callconv(.Inline) bool {
        return this.b.set_property_borders(name, value);
    }
    fn get_property_flt(this: *const Sandbox, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        //TODO
        return 0.0;
    }
    fn update(this: *Sandbox, curArea: R.FRect) Error!void {
        _ = curArea;
        const srcArea = this.b.borders.get_source_area(this.b.size.toRect());
        this.b.renderer.copyPartial(gui.buttonTemplate, srcArea) catch |e| return gui.convert_sdl2_error(e);
        var i: u32 = 0;
        var n: u32 = 0;
        const cellSize = 64.0*this.pow.scale;
        this.pow.posX += this.pow.deltaX;
        this.pow.posY += this.pow.deltaY;
        var dstArea = R.FRect{
            .x = 0,
            .y = 0,
            .w = cellSize,
            .h = cellSize,
        };
        while (n < this.mapm.height()) : (n += 1) {
            i = 0;
            while (i < this.mapm.width()) : (i += 1) {
                const biasX = this.pow.posX - curArea.w/2.0;
                const biasY = this.pow.posY - curArea.h/2.0;
                dstArea.x = @intToFloat(f32, i)*dstArea.w + biasX;
                dstArea.y = @intToFloat(f32, n)*dstArea.h + biasY;
                const x = @intCast(i32, @intCast(i64, i) - this.mapm.x_right());
                const y = @intCast(i32, @intCast(i64, n) - this.mapm.y_bottom());
                const texture = this.uTxs.items[this.mapm.get(x, y).texId];
                this.b.renderer.copyOriginal(texture.data, dstArea)
                    catch |e| return gui.convert_sdl2_error(e);
            }
        }
    }
    fn init(this: *Sandbox, width: u32, height: u32) callconv(.Inline) void {
        this.mapm = MapMesh.create(width, height, 0);
    }
    fn set_size(this: *Sandbox, w: u32, h: u32) callconv(.Inline) gui.Error!void {
        return this.mapm.resize(w, h);
    }
    fn register_texture(this: *Sandbox, tid: []const u8) callconv(.Inline) u32 {
        const texture = gui.resources.get_texture(tid) orelse {
            gui.handle_error(Error.ObjectNotFound, @src(), tid);
            return 0; //default texture
        };
        const ret = @intCast(u32, this.uTxs.items.len);
        this.uTxs.append(gui.allocator, texture) catch {
            gui.handle_error(Error.OutOfMemory, @src(), tid);
            return 0;
        };
        return ret;
    }
    fn set_map_status(this: *Sandbox, view: *I.MapView) gui.Error!void {
        return this.mapm.set_batch(view);
    }
    pub fn handle_mouse_wheel(this: *Sandbox, curArea: R.IRect, pos: R.IPoint, dir: i8) void {
        _ = curArea;
        _ = pos;
        if (dir > 0) {
            this.pow.scale *= 1.05;
        } else {
            this.pow.scale /= 1.05;
        }
    }
    fn mouse_cursor_entered(this: *Sandbox, pos: R.IPoint, delta: R.IPoint) void {
        _ = pos;
        _ = delta;
        this.pow.deltaX = 0;
        this.pow.deltaY = 0;
    }
    fn mouse_cursor_leaved(this: *Sandbox, pos: R.IPoint, delta: R.IPoint) void {
        _ = pos;
        if (delta.x > 0) {
            this.pow.deltaX = -1;
        }
        if (delta.x < 0) {
            this.pow.deltaX = 1;
        }
        if (delta.y > 0) {
            this.pow.deltaY = -1;
        }
        if (delta.y < 0) {
            this.pow.deltaY = 1;
        }
    }
    const Export = struct {
        const Funcs = struct {
            fn convert(iwgt: I.SandboxPtr, iid: I.InterfaceId) callconv(.C) I.GenericInterface {
                return Sandbox.convertSandbox(@ptrCast(*Sandbox, iwgt), iid);
            }
            fn destroy(iwgt: I.SandboxPtr) callconv(.C) void {
                Sandbox.destroy(@ptrCast(*Sandbox, iwgt));
            }
            fn set_size(iwgt: I.SandboxPtr, w: u32, h: u32) callconv(.C) I.ErrorNum {
                Sandbox.set_size(@ptrCast(*Sandbox, iwgt), w, h) catch |e| {
                    gui.handle_error(e, @src(), "");
                    return I.ErrorNum.OutOfMemory;
                };
                return I.ErrorNum.None;
            }
            fn add_texture(iwgt: I.SandboxPtr, value: F.String) callconv(.C) u32 {
                return Sandbox.register_texture(@ptrCast(*Sandbox, iwgt), value.from());
            }
            fn set_map_status(iwgt: I.SandboxPtr, view: *I.MapView) callconv(.C) I.ErrorNum {
                defer view.destroy(view);
                Sandbox.set_map_status(@ptrCast(*Sandbox, iwgt), view) catch |e| {
                    gui.handle_error(e, @src(), "");
                    switch (e) {
                        Error.OutOfMemory => return I.ErrorNum.OutOfMemory,
                        Error.InvalidObject => return I.ErrorNum.InvalidObject,
                        else => {}
                    }
                };
                return I.ErrorNum.None;
            }
        };
        fn generate() I.SandboxVirtual {
            return .{
                .convert = Funcs.convert,
                .destroy = Funcs.destroy,
                .set_size = Funcs.set_size,
                .add_texture = Funcs.add_texture,
                .set_map_status = Funcs.set_map_status,
            };
        }
    };
};

const Toolbox = struct {
    b: Widget.Base,

    const vprivate = Widget.Virtual.generate(Toolbox);
    const vwidget = Widget.Export.generate(Toolbox);

    fn create(rend: R.Renderer) Error!Widget {
        var toolbox = gui.allocator.create(Toolbox) catch return Error.OutOfMemory;
        toolbox.* = .{
            .b = .{
                .renderer = rend,
                .size = .{ .x = 200, .y = 200, },
            }
        };
        return Widget{ .vptr = &vprivate, .inst = @ptrCast(IPtr, toolbox), };
    }
    fn destroy(this: *Toolbox) callconv(.Inline) void {
        gui.allocator.destroy(this);
    }
    fn convertWidget(this: *Toolbox, iid: I.InterfaceId) I.GenericInterface {
        _ = iid;
        _ = this;
        return I.GenericInterface.zero;
    }
    fn set_property_flt(this: *Toolbox, name: []const u8, value: f64) callconv(.Inline) bool {
        return this.b.set_property_borders(name, value);
    }
    fn get_property_flt(this: *const Toolbox, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        //TODO
        return 0.0;
    }
    fn update(this: *Toolbox, curArea: R.FRect) Error!void {
        _ = curArea;
        const srcArea = this.b.borders.get_source_area(this.b.size.toRect());
        this.b.renderer.copyPartial(gui.buttonTemplate, srcArea) catch |e| return gui.convert_sdl2_error(e);
    }
};

const Button = struct {
    b: Widget.Base,
    label: [:0]const u8 = "",
    actions: Actions,
    texture: R.Texture,
    font: R.Font,
    fontLoaded: bool = false,

    const Actions = struct {
        click: F.Action = undefined,
    };

    const vprivate = Widget.Virtual.generate(Button);
    const vwidget = Widget.Export.generate(Button);
    const vexport = Export.generate();

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
            .font = undefined,
        };
        try button.draw_button();
        return Widget{ .vptr = &vprivate, .inst = @ptrCast(IPtr, button), };
    }
    fn destroy(this: *Button) callconv(.Inline) void {
        if (this.label.len != 0) gui.allocator.free(this.label);
        this.texture.destroy();
        gui.allocator.destroy(this);
    }
    fn draw_button(this: *Button) Error!void {
        {
            this.*.b.renderer.setTarget(this.*.texture) catch |e| return gui.convert_sdl2_error(e);
            defer this.*.b.renderer.freeTarget() catch unreachable;
            this.*.b.renderer.copyFull(gui.buttonTemplate) catch |e| return gui.convert_sdl2_error(e);
        }
        if (this.label.len != 0 and this.fontLoaded) {
            const text = this.font.renderText(this.label, .{ .r = 255, .g = 255, .b = 255, .a = 255, })
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
                this.*.b.renderer.copyOriginal(texttex, inscribed.convert(R.FRect)) catch |e| return gui.convert_sdl2_error(e);
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
            this.set_label(value);
            return true;
        }
        return false;
    }
    fn set_property_flt(this: *Button, name: []const u8, value: f64) callconv(.Inline) bool {
        return this.b.set_property_borders(name, value);
    }
    fn get_property_str(this: *const Button, name: []const u8) []const u8 {
        _ = this;
        _ = name;
        //TODO
        return "";
    }
    fn get_property_flt(this: *const Button, name: []const u8) callconv(.Inline) f64 {
        _ = this;
        _ = name;
        //TODO
        return 0.0;
    }
    fn set_label(this: *Button, value: []const u8) void {
        if (this.label.len != 0) gui.allocator.free(this.label);
        const label = gui.allocator.dupeZ(u8, value);
        _ = label catch |e| {
            gui.handle_error(e, @src(), "");
        };
        this.label = label catch "";
        this.draw_button() catch |e| {
            gui.handle_error(e, @src(), "");
        };
    }
    fn set_font(this: *Button, font: R.Font) void {
        this.font = font;
        this.fontLoaded = true;
        this.draw_button() catch |e| {
            gui.handle_error(e, @src(), "");
        };
    }
    fn update(this: *Button, curArea: R.FRect) Error!void {
        _ = curArea;
        const srcArea = this.b.borders.get_source_area(this.b.size.toRect());
        this.b.renderer.copyPartial(this.texture, srcArea) catch |e| return gui.convert_sdl2_error(e);
    }
    fn convertWidget(this: *Button, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Button => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vexport), },
            else => return I.GenericInterface.zero,
        };
    }
    fn convertButton(this: *Button, iid: I.InterfaceId) I.GenericInterface {
        return switch(iid) {
            .Widget => return .{ .data = @ptrToInt(this), .vptr = @ptrToInt(&vwidget), },
            else => return I.GenericInterface.zero,
        };
    }
    const Export = struct {
        const Funcs = struct {
            fn convert(iwgt: I.ButtonPtr, iid: I.InterfaceId) callconv(.C) I.GenericInterface {
                return Button.convertButton(@ptrCast(*Button, iwgt), iid);
            }
            fn destroy(iwgt: I.ButtonPtr) callconv(.C) void {
                Button.destroy(@ptrCast(*Button, iwgt));
            }
            fn set_label(iwgt: I.ButtonPtr, value: F.String) callconv(.C) void {
                Button.set_label(@ptrCast(*Button, iwgt), value.from());
            }
            fn set_font(iwgt: I.ButtonPtr, font: I.Font) callconv(.C) void {
                Button.set_font(@ptrCast(*Button, iwgt), @bitCast(R.Font, @ptrToInt(font)));
            }
        };
        fn generate() I.ButtonVirtual {
            return .{
                .convert = Funcs.convert,
                .destroy = Funcs.destroy,
                .set_label = Funcs.set_label,
                .set_font = Funcs.set_font,
            };
        }
    };
};

pub fn nearf(lhs: f32, rhs: f32, tolerance: f32) bool {
    return lhs - tolerance <= rhs and lhs + tolerance >= rhs;
}

test "widget borders and scaling" {
    const expect = std.testing.expect;
    const source = R.IRect{
        .x = 100,
        .y = 100,
        .w = 100,
        .h = 100,
    };
    const destination = R.FRect{
        .x = 200,
        .y = 200,
        .w = 200,
        .h = 200,
    };
    {
        var borders = Widget.Borders{
            .left = -1.1,
            .right = -0.1,
            .top = -0.9,
            .bottom = 0.1,
        };
        borders.update();
        try expect(nearf(borders.ssX, 1.0, 0.001));
        try expect(nearf(borders.ssW, 0.0, 0.001));
        try expect(nearf(borders.ssY, 0.9, 0.001));
        try expect(nearf(borders.ssH, 0.1, 0.001));
        try expect(nearf(borders.sdX, 0.0, 0.001));
        try expect(nearf(borders.sdW, 0.0, 0.001));
        try expect(nearf(borders.sdY, 0.0, 0.001));
        try expect(nearf(borders.sdH, 0.1, 0.001));

        const s = borders.get_source_area(source);
        const d = borders.get_destination_area(destination);
        try expect(s.x == 200);
        try expect(s.w == 0);
        try expect(s.y == 190);
        try expect(s.h == 10);
        try expect(d.x == 200);
        try expect(d.w == 0);
        try expect(d.y == 200);
        try expect(d.h == 20);
    }
    {
        var borders = Widget.Borders{
            .left = -1.5,
            .right = 0.5,
            .top = -1.5,
            .bottom = -1.0,
        };
        borders.update();
        try expect(nearf(borders.ssX, 0.75, 0.001));
        try expect(nearf(borders.ssW, 0.25, 0.001));
        try expect(nearf(borders.ssY, 1.0, 0.001));
        try expect(nearf(borders.ssH, 0.0, 0.001));
        try expect(nearf(borders.sdX, 0.0, 0.001));
        try expect(nearf(borders.sdW, 0.5, 0.001));
        try expect(nearf(borders.sdY, 0.0, 0.001));
        try expect(nearf(borders.sdH, 0.0, 0.001));

        const s = borders.get_source_area(source);
        const d = borders.get_destination_area(destination);
        try expect(s.x == 175);
        try expect(s.w == 25);
        try expect(s.y == 200);
        try expect(s.h == 0);
        try expect(d.x == 200);
        try expect(d.w == 100);
        try expect(d.y == 200);
        try expect(d.h == 0);
    }
    {
        var borders = Widget.Borders{
            .left = 0.25,
            .right = 0.75,
            .top = -0.5,
            .bottom = 1.5,
        };
        borders.update();
        try expect(nearf(borders.ssX, 0.0, 0.001));
        try expect(nearf(borders.ssW, 1.0, 0.001));
        try expect(nearf(borders.ssY, 0.25, 0.001));
        try expect(nearf(borders.ssH, 0.5, 0.001));
        try expect(nearf(borders.sdX, 0.25, 0.001));
        try expect(nearf(borders.sdW, 0.5, 0.001));
        try expect(nearf(borders.sdY, 0.0, 0.001));
        try expect(nearf(borders.sdH, 1.0, 0.001));

        const s = borders.get_source_area(source);
        const d = borders.get_destination_area(destination);
        try expect(s.x == 100);
        try expect(s.w == 100);
        try expect(s.y == 125);
        try expect(s.h == 50);
        try expect(d.x == 250);
        try expect(d.w == 100);
        try expect(d.y == 200);
        try expect(d.h == 200);
    }
    {
        var borders = Widget.Borders{
            .left = 0.5,
            .right = 2.5,
            .top = 1.5,
            .bottom = 2,
        };
        borders.update();
        try expect(nearf(borders.ssX, 0.0, 0.001));
        try expect(nearf(borders.ssW, 0.25, 0.001));
        try expect(nearf(borders.ssY, 0.0, 0.001));
        try expect(nearf(borders.ssH, 0.0, 0.001));
        try expect(nearf(borders.sdX, 0.5, 0.001));
        try expect(nearf(borders.sdW, 0.5, 0.001));
        try expect(nearf(borders.sdY, 1.0, 0.001));
        try expect(nearf(borders.sdH, 0.0, 0.001));

        const s = borders.get_source_area(source);
        const d = borders.get_destination_area(destination);
        try expect(s.x == 100);
        try expect(s.w == 25);
        try expect(s.y == 100);
        try expect(s.h == 0);
        try expect(d.x == 300);
        try expect(d.w == 100);
        try expect(d.y == 400);
        try expect(d.h == 0);
    }
}
