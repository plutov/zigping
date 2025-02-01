const std = @import("std");
const tui = @import("tui.zig");

// disable debug log
pub const log_level: std.log.Level = .info;

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

    var app = try tui.App.init(allocator, hostnames);
    defer app.deinit();

    try app.run();
}
