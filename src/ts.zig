const std = @import("std");
const crawler = @import("crawler.zig");

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
        // free results
        for (self.intervals.items) |interval| {
            self.allocator.free(interval.crawl_results);
        }
        self.intervals.deinit();

        // free hostname copies in the hash map
        var it = self.hostnamesStats.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.hostnamesStats.deinit();
    }

    pub fn getLastNIntervals(self: *TimeSeries, n: usize) []Interval {
        const len = self.intervals.items.len;

        if (len == 0) {
            return &[_]Interval{};
        }

        var start_index: usize = 0;
        if (len >= n) {
            start_index = len - n;
        }

        return self.intervals.items[start_index..];
    }

    fn roundToNearest50(value: i32, roundUp: bool) i32 {
        const remainder = std.math.mod(i32, value, 50) catch blk: {
            break :blk 0;
        };

        if (roundUp) {
            if (remainder == 0) {
                return value;
            }

            return value + (50 - remainder);
        }

        return value - remainder;
    }

    pub fn addResults(self: *TimeSeries, results: []const crawler.CrawlResult) !void {
        const results_copy = try self.allocator.dupe(crawler.CrawlResult, results);

        // update min and max latency
        for (results_copy) |result| {
            if (self.intervals.items.len == 0) {
                self.min_latency = result.latency_ms;
            } else {
                self.min_latency = @min(result.latency_ms, self.min_latency);
            }
            self.max_latency = @max(result.latency_ms, self.max_latency);

            // round
            self.min_latency = roundToNearest50(self.min_latency, false);
            self.max_latency = roundToNearest50(self.max_latency, true);
        }

        try self.intervals.append(.{
            .timestamp = std.time.timestamp(),
            .crawl_results = results_copy,
        });

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
                const hostname_copy = try self.allocator.dupe(u8, result.hostname);

                var hostname_stats = self.hostnamesStats.get(hostname_copy);
                if (hostname_stats) |*stats| {
                    const _latency_ms: f64 = @floatFromInt(result.latency_ms);
                    const _total_latency = stats.total_latency + _latency_ms;
                    const _total_results = stats.total_results + 1;
                    const _avg_latency = _total_latency / _total_results;

                    try self.hostnamesStats.put(hostname_copy, .{
                        .min_latency = @min(stats.min_latency, result.latency_ms),
                        .max_latency = @max(stats.max_latency, result.latency_ms),
                        .total_latency = _total_latency,
                        .total_results = _total_results,
                        .avg_latency = _avg_latency,
                    });

                    // we don't need this copy anymore
                    self.allocator.free(hostname_copy);
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
