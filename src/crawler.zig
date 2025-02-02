const std = @import("std");
const tui = @import("tui.zig");
const vaxis = @import("vaxis");

// max size for server headers
const headers_max_size = 4096;

pub const CrawlResult = struct {
    success: bool,
    hostname: []const u8,
    latency_ms: i32,
    status_code: std.http.Status,
};

pub fn crawl(allocator: std.mem.Allocator, hostname: []const u8) !CrawlResult {
    // Allocate a buffer for server headers
    var buf: [headers_max_size]u8 = undefined;

    const hostname_with_scheme = try std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}", .{ "https://", hostname });
    defer std.heap.page_allocator.free(hostname_with_scheme);

    const uri = std.Uri.parse(hostname) catch blk: {
        // try with https scheme
        const uri_with_scheme = try std.Uri.parse(hostname_with_scheme);
        break :blk uri_with_scheme;
    };

    // http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Start the HTTP request
    var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();

    var timer = try std.time.Timer.start();

    try req.send();
    try req.finish();
    try req.wait();

    const latency: f64 = @floatFromInt(timer.read());
    const latency_ms = @as(i32, @intFromFloat(latency / std.time.ns_per_ms));

    return CrawlResult{
        .success = true,
        .hostname = hostname,
        .latency_ms = latency_ms,
        .status_code = req.response.status,
    };
}

// blocking function
pub fn start(hostnames: [][]const u8, allocator: std.mem.Allocator, loop: *vaxis.Loop(tui.Event), running: *std.atomic.Value(bool)) !void {
    // Store results here
    var results = std.ArrayList(CrawlResult).init(allocator);
    defer results.deinit();

    while (running.load(.monotonic)) {
        for (hostnames) |hostname| {
            const result = crawl(allocator, hostname) catch blk: {
                const empty_res: CrawlResult = .{
                    .success = false,
                    .hostname = hostname,
                    .latency_ms = 0,
                    .status_code = std.http.Status.internal_server_error,
                };
                break :blk empty_res;
            };

            try results.append(result);
        }

        loop.postEvent(.{
            .crawl_results = results.items[results.items.len - hostnames.len .. results.items.len],
        });

        std.time.sleep(std.time.ns_per_s);
    }
}
