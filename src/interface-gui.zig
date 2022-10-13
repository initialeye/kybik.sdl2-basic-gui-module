const Fw = @import("framework.zig");

pub const WinPtr = *align(@alignOf(*void)) opaque{};
pub const WdgPtr = *align(@alignOf(*void)) opaque{};
pub const Texture = *opaque{};

pub const API_VERSION:usize = 0;
pub const INTERFACE_VERSION = Fw.CompatVersion.init(0, 0);

pub const ATTRIBUTES = Fw.Attributes {
    .multiple_versions = 0,
    .multiple_modules  = 0,
};

pub const TextureSize = extern struct {
    x: u32,
    y: u32,
};

pub fn get_func_info(fnptr: *const Fw.FnPtr) callconv(.C) Fw.String {
    _ = fnptr;
    return Fw.String.init("1234");
}

pub const InterfaceId = enum(u32) {
    Widget,
    Window,
};

pub const ModuleVirtual = extern struct {
    create_window: fn(Fw.String, u16, u16) callconv(.C) Widget,
    load_texture: fn(Fw.String) callconv(.C) ?Texture,
    get_texture: fn(Fw.String) callconv(.C) ?Texture,
    get_texture_count: fn() callconv(.C) usize,
    get_texture_path: fn(usize) callconv(.C) Fw.String,
    get_texture_size: fn(Texture) callconv(.C) TextureSize,
};

pub const WidgetVirtual = extern struct {
    create: fn(WdgPtr, Fw.String) callconv(.C) Widget,
    destroy: fn(WdgPtr) callconv(.C) void,
    convert: fn(WdgPtr, InterfaceId) callconv(.C) GenericInterface,
    set_property_str: fn(WdgPtr, Fw.String, Fw.String) callconv(.C) bool,
    set_property_int: fn(WdgPtr, Fw.String, i64) callconv(.C) bool,
    set_property_flt: fn(WdgPtr, Fw.String, f64) callconv(.C) bool,
    get_property_str: fn(WdgPtr, Fw.String) callconv(.C) Fw.String,
    get_property_int: fn(WdgPtr, Fw.String) callconv(.C) i64,
    get_property_flt: fn(WdgPtr, Fw.String) callconv(.C) f64,
    __original: fn() callconv(.C) usize,
};

pub const WindowVirtual = extern struct {
    destroy: fn(WinPtr) callconv(.C) void,
    convert: fn(WinPtr, InterfaceId) callconv(.C) GenericInterface,
};

pub const GenericInterface = extern struct {
    data: usize,
    vptr: usize,

    pub const zero = GenericInterface{ .data = 0, .vptr = 0, };
 
    pub fn isNull(g: GenericInterface) bool {
        return g.data == 0;
    }
};

pub const Widget = extern struct {
    data: WdgPtr,
    vptr: *const WidgetVirtual,

    // It is more convenient to use these functions if this module is imported
    pub fn create(w: Widget, n: Fw.String) Widget {
        return w.vptr.create(w.data, n);
    }
    pub fn destroy(w: Widget) void {
        return w.vptr.destroy(w.data);
    }
    pub fn convert(w: Widget, i: InterfaceId) GenericInterface {
        return w.vptr.convert(w.data, i);
    }
    pub fn set_property_str(w: Widget, name: Fw.String, value: Fw.String) bool {
        return w.vptr.set_property_str(w.data, name, value);
    }
    pub fn set_property_int(w: Widget, name: Fw.String, value: i64) bool {
        return w.vptr.set_property_int(w.data, name, value);
    }
    pub fn set_property_flt(w: Widget, name: Fw.String, value: f64) bool {
        return w.vptr.set_property_flt(w.data, name, value);
    }
    pub fn get_property_str(w: Widget, name: Fw.String) Fw.String {
        return w.vptr.get_property_str(w.data, name);
    }
    pub fn get_property_int(w: Widget, name: Fw.String) i64 {
        return w.vptr.get_property_int(w.data, name);
    }
    pub fn get_property_flt(w: Widget, name: Fw.String) f64 {
        return w.vptr.get_property_flt(w.data, name);
    }
};

pub const Window = extern struct {
    data: WinPtr,
    vptr: *const WindowVirtual,

    pub fn destroy(w: Window) void {
        return w.vptr.destroy(w.data);
    }
    pub fn convert(w: Window, i: InterfaceId) GenericInterface {
        return w.vptr.convert(w.data, i);
    }
};
