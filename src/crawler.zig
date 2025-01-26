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
