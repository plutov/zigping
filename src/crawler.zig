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

    var uri = try std.Uri.parse(hostname);
    // Add https:// if no scheme is present
    if (uri.scheme.len == 0) {
        const hostname_with_schema = try std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}", .{ "https://", hostname });
        defer std.heap.page_allocator.free(hostname_with_schema);

        uri = try std.Uri.parse(hostname_with_schema);
    }

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
    // http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    while (running.load(std.builtin.AtomicOrder.acquire)) {
        // Store results here
        var results = std.ArrayList(CrawlResult).init(allocator);
        defer results.deinit();
        try results.resize(hostnames.len);

        var wg = std.Thread.WaitGroup{};
        wg.reset();

        for (hostnames, 0..) |hostname, i| {
            wg.start();

            // Spawn a thread for each url
            _ = try std.Thread.spawn(.{}, struct {
                fn worker(_hostname: []const u8, _client: *std.http.Client, _wg: *std.Thread.WaitGroup, _results: *std.ArrayList(CrawlResult), _i: usize) !void {
                    defer _wg.finish();

                    const result = crawl(_client, _hostname) catch {
                        try _results.insert(_i, .{
                            .success = false,
                            .hostname = _hostname,
                            .latency_ms = 0,
                            .status_code = std.http.Status.internal_server_error,
                        });
                        return;
                    };

                    try _results.insert(_i, result);
                }
            }.worker, .{ hostname, &client, &wg, &results, i });
        }
        wg.wait();

        // Post all results at once
        loop.postEvent(.{
            .crawl_results = results.items,
        });

        std.time.sleep(std.time.ns_per_s);
    }
}
