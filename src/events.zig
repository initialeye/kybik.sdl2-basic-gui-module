const std = @import("std");
const gui = @import("gui.zig");
const Fw = @import("framework.zig");
const sdl2 = @import("sdl2.zig");

const handler: sdl2.EventHandler = .{
    .quit_event = quit_event,
    .button_event = button_event,
    .motion_event = mouse_motion_event,
    .wheel_event = mouse_wheel_event,
};

pub fn handle_all() void {
    handler.handle();
}

fn mouse_motion_event(event: *sdl2.Event.MouseMotion) void {
    gui.mouse_moved(event.windowID,
        .{ .x = @intCast(i16, event.x), .y = @intCast(i16, event.y), },
        .{ .x = @intCast(i16, event.xrel), .y = @intCast(i16, event.yrel), }
    );
}
fn mouse_wheel_event(event: *sdl2.Event.MouseWheel) void {
    gui.mouse_wheel(event.windowID, @intCast(i8, event.y));
}
fn quit_event(event: *sdl2.Event.Quit) void {
    _ = event;
    gui.core.exit();
}
fn button_event(event: *sdl2.Event.MouseButton) void {
    if(event.state == @enumToInt(sdl2.ButtonState.pressed)) {
        gui.mouse_clicked(event.windowID, .{ .x = @intCast(i16, event.x), .y = @intCast(i16, event.y), });
    }
}
