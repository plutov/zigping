const std = @import("std");
const crawler = @import("crawler.zig");

// max amount of intervals to store, we assume it's enough'
const maxIntervals: i32 = 1024;

pub const Interval = struct {
    timestamp: i64,
    crawl_results: []const crawler.CrawlResult,
};

const HostnameStats = struct {
    min_latency: i32,
    max_latency: i32,
    avg_latency: f64,
    total_latency: f64,
    total_results: f64,
};

pub const TimeSeries = struct {
    allocator: std.mem.Allocator,
    intervals: std.ArrayList(Interval),
    min_latency: i32,
    max_latency: i32,
    avg_latency: f64,
    hostnamesStats: std.StringHashMap(HostnameStats),

    pub fn init(allocator: std.mem.Allocator) !TimeSeries {
        return .{
            .allocator = allocator,
            .intervals = std.ArrayList(Interval).init(allocator),
            // starting values
            .min_latency = 0,
            .max_latency = 100,
            .avg_latency = 50,
            .hostnamesStats = std.StringHashMap(HostnameStats).init(allocator),
        };
    }

    pub fn deinit(self: *TimeSeries) void {
        self.intervals.deinit();

        // free hostname copies in the hash map
        var it = self.hostnamesStats.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.hostnamesStats.deinit();
    }

    pub fn addResults(self: *TimeSeries, results: []const crawler.CrawlResult) !void {
        try self.intervals.append(.{
            .timestamp = std.time.timestamp(),
            .crawl_results = results,
        });

        while (self.intervals.items.len > maxIntervals) {
            _ = self.intervals.orderedRemove(0);
        }

        // update min and max latency
        for (results) |result| {
            self.min_latency = @min(result.latency_ms, self.min_latency);
            self.max_latency = @max(result.latency_ms, self.max_latency);
        }

        // calculate average latency from all intervals
        var total_latency: f64 = 0;
        var total_results: f64 = 0;

        for (self.intervals.items) |interval| {
            for (interval.crawl_results) |result| {
                total_latency += @floatFromInt(result.latency_ms);
                total_results += 1;
            }
        }

        if (total_results > 0) {
            self.avg_latency = total_latency / total_results;
        }

        // calculate avergaes per hostname
        for (self.intervals.items) |interval| {
            for (interval.crawl_results) |result| {
                const hostname_copy = try self.allocator.dupeZ(u8, result.hostname);

                var hostname_stats = self.hostnamesStats.get(hostname_copy);
                if (hostname_stats) |*stats| {
                    self.allocator.free(hostname_copy);

                    stats.min_latency = @min(stats.min_latency, result.latency_ms);
                    stats.max_latency = @max(stats.max_latency, result.latency_ms);
                    stats.total_latency += @floatFromInt(result.latency_ms);
                    stats.total_results += 1;
                    stats.avg_latency = stats.total_latency / stats.total_results;
                } else {
                    try self.hostnamesStats.put(hostname_copy, .{
                        .min_latency = result.latency_ms,
                        .max_latency = result.latency_ms,
                        .avg_latency = @floatFromInt(result.latency_ms),
                        .total_latency = @floatFromInt(result.latency_ms),
                        .total_results = 1,
                    });
                }
            }
        }
    }
};
