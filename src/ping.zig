const std = @import("std");
const crawler = @import("crawler.zig");
const vaxis = @import("vaxis");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // command-line args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) {
        std.debug.print("Usage: zigping <hostname1> <hostname2> ...\n", .{});
        return;
    }
    const hostnames = args[1..];

    // Run crawler in thread
    _ = try std.Thread.spawn(.{}, struct {
        fn worker(_hostnames: [][]const u8, _allocator: std.mem.Allocator) !void {
            try crawler.start(_hostnames, _allocator);
        }
    }.worker, .{ hostnames, allocator });

    // Initialize a tty
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    var text_input = vaxis.widgets.TextInput.init(allocator, &vx.unicode);
    defer text_input.deinit();

    var color_idx: u8 = 0;

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                color_idx = switch (color_idx) {
                    255 => 0,
                    else => color_idx + 1,
                };
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else {
                    try text_input.update(.{ .key_press = key });
                }
            },
            .winsize => |ws| try vx.resize(allocator, tty.anyWriter(), ws),
            else => {},
        }

        const win = vx.window();
        win.clear();

        // Create a style
        const style: vaxis.Style = .{
            .fg = .{ .index = color_idx },
        };

        // Create a bordered child window
        const child = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = 40,
            .height = 3,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        text_input.draw(child);

        // Render the screen
        try vx.render(tty.anyWriter());
    }
}
