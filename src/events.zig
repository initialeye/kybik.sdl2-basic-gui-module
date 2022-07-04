const std = @import("std");
const gui = @import("gui.zig");
const Fw = @import("framework.zig");
const sdl2 = @import("sdl2.zig");

const handler: sdl2.EventHandler = .{
    .quit_event = quit_event,
    .button_event = button_event,
};

pub fn handle_all() void {
    handler.handle();
}

fn quit_event(event: *sdl2.Event.Quit) void {
    _ = event;
    gui.core.exit();
}

fn button_event(event: *sdl2.Event.MouseButton) void {
    _ = event;
    if(event.state == @enumToInt(sdl2.ButtonState.pressed)) {
        gui.mouse_clicked(event.windowID, .{ .x = @intCast(i16, event.x), .y = @intCast(i16, event.y), });
    }
}
