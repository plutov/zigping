const std = @import("std");
// max size for server headers
const headers_max_size = 4096;

pub const CrawlResult = struct {
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
        .latency_ms = latency_ms,
        .status_code = req.response.status,
    };
}

// blocking function
pub fn start(hostnames: [][]const u8, allocator: std.mem.Allocator) !void {
    // http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    while (true) {
        var wg = std.Thread.WaitGroup{};
        wg.reset();

        for (hostnames) |hostname| {
            wg.start();

            // Spawn a thread for each url
            _ = try std.Thread.spawn(.{}, struct {
                fn worker(_hostname: []const u8, _client: *std.http.Client, _wg: *std.Thread.WaitGroup) void {
                    defer _wg.finish();

                    const result = crawl(_client, _hostname) catch |err| {
                        std.debug.print("error crawling {s}: {}\n", .{ _hostname, err });
                        return;
                    };

                    std.debug.print("host={s},status={d},latency={d}ms\n", .{ _hostname, result.status_code, result.latency_ms });
                }
            }.worker, .{ hostname, &client, &wg });
        }
        wg.wait();

        std.time.sleep(std.time.ns_per_s);
    }
}
