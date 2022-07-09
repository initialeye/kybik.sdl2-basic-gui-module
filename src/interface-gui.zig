const Fw = @import("framework.zig");

pub const WinPtr = *align(@alignOf(*void)) opaque{};
pub const WidPtr = *align(@alignOf(*void)) opaque{};

pub const API_VERSION:usize = 0;
pub const INTERFACE_VERSION = Fw.CompatVersion.init(0, 0);
pub const ATTRIBUTES = Fw.Attributes {
    .multiple_versions = 0,
    .multiple_modules  = 0,
};

pub fn get_func_info(fnptr: *const Fw.FnPtr) callconv(.C) Fw.String {
    _ = fnptr;
    return Fw.String.init("1234");
}

pub const Virtual = extern struct {
    create_window: fn(Fw.String) callconv(.C) WinPtr,
    update_window: fn(WinPtr) callconv(.C) void,
    create_widget: fn(WinPtr, ?WidPtr, Fw.String) callconv(.C) ?WidPtr,
    set_widget_property_str: fn(WidPtr, Fw.String, Fw.String) callconv(.C) bool,
    set_widget_property_int: fn(WidPtr, Fw.String, i64) callconv(.C) bool,
    set_widget_property_flt: fn(WidPtr, Fw.String, f64) callconv(.C) bool,
    get_widget_property_str: fn(WidPtr, Fw.String) callconv(.C) Fw.String,
    get_widget_property_int: fn(WidPtr, Fw.String) callconv(.C) i64,
    get_widget_property_flt: fn(WidPtr, Fw.String) callconv(.C) f64,
};
