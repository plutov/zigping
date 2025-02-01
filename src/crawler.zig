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

pub fn crawl(client: *std.http.Client, hostname: []const u8) !CrawlResult {
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
        .success = true,
        .hostname = hostname,
        .latency_ms = latency_ms,
        .status_code = req.response.status,
    };
}

// blocking function
pub fn start(hostnames: [][]const u8, allocator: std.mem.Allocator, loop: *vaxis.Loop(tui.Event), running: *std.atomic.Value(bool)) !void {
    // http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    while (running.load(std.builtin.AtomicOrder.acquire)) {
        var wg = std.Thread.WaitGroup{};
        wg.reset();

        for (hostnames) |hostname| {
            wg.start();

            // Spawn a thread for each url
            _ = try std.Thread.spawn(.{}, struct {
                fn worker(_hostname: []const u8, _client: *std.http.Client, _wg: *std.Thread.WaitGroup, _loop: *vaxis.Loop(tui.Event)) void {
                    defer _wg.finish();

                    const result = crawl(_client, _hostname) catch {
                        _loop.postEvent(.{
                            .crawl_result = CrawlResult{
                                .success = false,
                                .hostname = _hostname,
                                .latency_ms = 0,
                                .status_code = std.http.Status.internal_server_error,
                            },
                        });
                        return;
                    };

                    _loop.postEvent(.{
                        .crawl_result = result,
                    });
                }
            }.worker, .{ hostname, &client, &wg, loop });
        }
        wg.wait();

        std.time.sleep(std.time.ns_per_s);
    }
}
