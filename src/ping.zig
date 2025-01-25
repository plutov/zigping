// const vaxis = @import("vaxis");

const std = @import("std");
// const builtin = @import("builtin");
// const net = std.net;
const headers_max_size = 4096;

const CrawlResult = struct {
    latency_ms: i32,
    status_code: std.http.Status,
};

fn crawl(client: *std.http.Client, hostname: []const u8) !CrawlResult {
    // Allocate a buffer for server headers
    var buf: [headers_max_size]u8 = undefined;

    // Start the HTTP request
    const uri = try std.Uri.parse(hostname);
    var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();

    var timer = try std.time.Timer.start();

    try req.send();
    try req.finish();
    try req.wait();

    const latency: f64 = @floatFromInt(timer.read());
    const latency_ms = @as(i32, @intFromFloat(latency / std.time.ns_per_ms));

    return CrawlResult{
        .latency_ms = latency_ms,
        .status_code = req.response.status,
    };
}

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

    // http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    while (true) {
        for (hostnames) |hostname| {
            const result = try crawl(&client, hostname);
            std.debug.print("host={s},status={d},latency={d}ms\n", .{ hostname, result.status_code, result.latency_ms });
        }

        std.time.sleep(std.time.ns_per_s);
    }
}
