const std = @import("std");
const crawler = @import("crawler.zig");

// max amount of intervals to store, we assume it's enough'
const maxIntervals: i32 = 1024;

pub const Interval = struct {
    timestamp: i64,
    crawl_results: []const crawler.CrawlResult,
};

pub const TimeSeries = struct {
    allocator: std.mem.Allocator,
    intervals: std.ArrayList(Interval),
    min_latency: i32,
    max_latency: i32,
    avg_latency: f64,

    pub fn init(allocator: std.mem.Allocator) !TimeSeries {
        return .{
            .allocator = allocator,
            .intervals = std.ArrayList(Interval).init(allocator),
            // starting values
            .min_latency = 0,
            .max_latency = 100,
            .avg_latency = 50,
        };
    }

    pub fn deinit(self: *TimeSeries) void {
        self.intervals.deinit();
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
            if (result.latency_ms < self.min_latency) {
                self.min_latency = result.latency_ms;
            }
            if (result.latency_ms > self.max_latency) {
                self.max_latency = result.latency_ms;
            }
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
    }
};
