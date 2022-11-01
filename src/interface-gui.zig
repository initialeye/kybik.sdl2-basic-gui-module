const Fw = @import("framework.zig");

pub const WdgPtr = *align(Fw.stdalign) opaque{};
pub const WinPtr = *align(Fw.stdalign) opaque{};
pub const SandboxPtr = *align(Fw.stdalign) opaque{};
pub const ButtonPtr = *align(Fw.stdalign) opaque{};
pub const Texture = *align(Fw.stdalign) opaque{};
pub const Font = *align(Fw.stdalign) opaque{};

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
    Widget = 0,
    Window,
    Sandbox,
    Button,
};
pub const ErrorNum = enum(u32) {
    None = 0,
    OutOfMemory,
    InvalidObject,
};
pub const ResourceType = enum(u32) {
    Texture = 0,
    Surface,
    Font,
};

pub const MapView = extern struct {
    destroy: fn(*MapView) callconv(.C) void,
    data: [*]Cell,
    len: usize,
    ctx: Fw.CbCtx = .{},

    pub const Cell = extern struct {
        modelId: u32 = 0,
        status: u32 = 0,
    };
};

pub const ModuleVirtual = extern struct {
    create_window: fn(Fw.String, u16, u16) callconv(.C) Widget,
    load_textures: fn(Fw.String, Fw.String) callconv(.C) u64,
    load_fonts: fn(Fw.String, Fw.String, u16) callconv(.C) u64,
    get_texture: fn(Fw.String) callconv(.C) ?Texture,
    get_font: fn(Fw.String, u16) callconv(.C) ?Font,
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

pub const SandboxVirtual = extern struct {
    destroy: fn(SandboxPtr) callconv(.C) void,
    convert: fn(SandboxPtr, InterfaceId) callconv(.C) GenericInterface,
    set_size: fn(SandboxPtr, u32, u32) callconv(.C) ErrorNum,
    add_texture: fn(SandboxPtr, Fw.String) callconv(.C) u32,
    set_map_status: fn(SandboxPtr, *MapView) callconv(.C) ErrorNum,
};

pub const ButtonVirtual = extern struct {
    destroy: fn(ButtonPtr) callconv(.C) void,
    convert: fn(ButtonPtr, InterfaceId) callconv(.C) GenericInterface,
    set_label: fn(ButtonPtr, Fw.String) callconv(.C) void,
    set_font: fn(ButtonPtr, Font) callconv(.C) void,
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
pub const Sandbox = extern struct {
    data: SandboxPtr,
    vptr: *const SandboxVirtual,

    pub fn destroy(s: Sandbox) void {
        return s.vptr.destroy(s.data);
    }
    pub fn convert(s: Sandbox, i: InterfaceId) GenericInterface {
        return s.vptr.convert(s.data, i);
    }
    pub fn set_size(s: Sandbox, w: u32, h: u32) ErrorNum {
        return s.vptr.set_size(s.data, w, h);
    }
    pub fn add_texture(s: Sandbox, path: Fw.String) u32 {
        return s.vptr.add_texture(s.data, path);
    }
    pub fn set_map_status(s: Sandbox, view: *MapView) ErrorNum {
        return s.vptr.set_map_status(s.data, view);
    }
};
pub const Button = extern struct {
    data: ButtonPtr,
    vptr: *const ButtonVirtual,

    pub fn destroy(b: Button) void {
        return b.vptr.destroy(b.data);
    }
    pub fn convert(b: Button, i: InterfaceId) GenericInterface {
        return b.vptr.convert(b.data, i);
    }
    pub fn set_label(b: Button, label: Fw.String) void {
        return b.vptr.set_label(b.data, label);
    }
    pub fn set_font(b: Button, font: Font) void {
        return b.vptr.set_font(b.data, font);
    }
};
