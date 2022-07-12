const Fw = @import("framework.zig");

pub const WinPtr = *align(@alignOf(*void)) opaque{};
pub const WidPtr = *align(@alignOf(*void)) opaque{};
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

pub const Virtual = extern struct {
    create_window: fn(Fw.String, u16, u16) callconv(.C) ?WinPtr,
    update_window: fn(WinPtr) callconv(.C) void,
    window_widget: fn(WinPtr) callconv(.C) WidPtr,
    create_widget: fn(WidPtr, Fw.String) callconv(.C) ?WidPtr,
    set_widget_junction_point: fn(WidPtr, parX: i32, parY: i32, chX: i32, chY: i32, idx: u8) callconv(.C) bool,
    reset_widget_junction_point: fn(WidPtr, u8) callconv(.C) bool,
    set_widget_property_str: fn(WidPtr, Fw.String, Fw.String) callconv(.C) bool,
    set_widget_property_int: fn(WidPtr, Fw.String, i64) callconv(.C) bool,
    set_widget_property_flt: fn(WidPtr, Fw.String, f64) callconv(.C) bool,
    get_widget_property_str: fn(WidPtr, Fw.String) callconv(.C) Fw.String,
    get_widget_property_int: fn(WidPtr, Fw.String) callconv(.C) i64,
    get_widget_property_flt: fn(WidPtr, Fw.String) callconv(.C) f64,
    load_texture: fn(Fw.String) callconv(.C) ?Texture,
    get_texture: fn(Fw.String) callconv(.C) ?Texture,
    get_texture_size: fn(Texture) callconv(.C) TextureSize,
};

