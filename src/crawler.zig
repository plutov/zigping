const std = @import("std");
const tui = @import("tui.zig");
const vaxis = @import("vaxis");

// max size for server headers
const headers_max_size = 4096;

// max amount of intervals to store, we assume it's enough
const maxIntervals: i32 = 1024;

pub const CrawlResult = struct {
    success: bool,
    hostname: []const u8,
    latency_ms: i32,
    status_code: std.http.Status,
};

pub const Crawler = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(CrawlResult),

    pub fn init(allocator: std.mem.Allocator) Crawler {
        return Crawler{
            .allocator = allocator,
            .results = std.ArrayList(CrawlResult).init(allocator),
        };
    }

    pub fn deinit(self: *Crawler) void {
        self.results.deinit();
    }

    pub fn crawl(self: *Crawler, allocator: std.mem.Allocator, hostname: []const u8) !CrawlResult {
        // Allocate a buffer for server headers
        var buf: [headers_max_size]u8 = undefined;

        const hostname_with_scheme = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ "https://", hostname });
        defer self.allocator.free(hostname_with_scheme);

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

    pub fn start(self: *Crawler, hostnames: [][]const u8, loop: *vaxis.Loop(tui.Event), running: *std.atomic.Value(bool)) void {
        while (running.load(.monotonic)) {
            for (hostnames) |hostname| {
                const result = self.crawl(self.allocator, hostname) catch blk: {
                    const empty_res: CrawlResult = .{
                        .success = false,
                        .hostname = hostname,
                        .latency_ms = 0,
                        .status_code = std.http.Status.internal_server_error,
                    };
                    break :blk empty_res;
                };

                self.results.append(result) catch {};
            }

            loop.postEvent(.{
                .crawl_results = self.results.items[self.results.items.len - hostnames.len .. self.results.items.len],
            });

            while (self.results.items.len > maxIntervals) {
                _ = self.results.orderedRemove(0);
            }

            std.time.sleep(std.time.ns_per_s);
        }
    }
};
