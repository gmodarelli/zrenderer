const builtin = @import("builtin");
const std = @import("std");
const win32 = @import("win32");
const w = win32.base;
const common = @import("common");
const lib = common.library;
const r = @import("renderer.zig");

const hrPanic = lib.hrPanic;
const hrPanicOnFail = lib.hrPanicOnFail;

pub fn main() anyerror!void {
    const window_name = "zrenderer";
    const window_width = 1920;
    const window_height = 1080;

    lib.init();
    defer lib.deinit();

    var gpa_allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator_state.deinit();
        std.debug.assert(leaked == false);
    }
    const gpa_allocator = gpa_allocator_state.allocator();

    const window = lib.initWindow(gpa_allocator, window_name, window_width, window_height) catch unreachable;
    defer lib.deinitWindow(gpa_allocator);

    var renderer = r.Renderer.init(gpa_allocator, window);
    defer renderer.deinit();

    renderer.loadScene(gpa_allocator, "content/models/test_level.gltf");

    while (true) {
        var message = std.mem.zeroes(w.user32.MSG);
        const has_message = w.user32.peekMessageA(&message, null, 0, 0, w.user32.PM_REMOVE) catch unreachable;
        if (has_message) {
            _ = w.user32.translateMessage(&message);
            _ = w.user32.dispatchMessageA(&message);
            if (message.message == w.user32.WM_QUIT) {
                break;
            }
        } else {
            renderer.update();
            renderer.render();
        }
    }
}