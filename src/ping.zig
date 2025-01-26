// const vaxis = @import("vaxis");

const std = @import("std");
const crawler = @import("crawler.zig");

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
        var wg = std.Thread.WaitGroup{};
        wg.reset();

        for (hostnames) |hostname| {
            wg.start();

            // Spawn a thread for each url
            _ = try std.Thread.spawn(.{}, struct {
                fn worker(h: []const u8, c: *std.http.Client, w: *std.Thread.WaitGroup) void {
                    defer w.finish();

                    const result = crawler.crawl(c, h) catch |err| {
                        std.debug.print("error crawling {s}: {}\n", .{ h, err });
                        return;
                    };

                    std.debug.print("host={s},status={d},latency={d}ms\n", .{ h, result.status_code, result.latency_ms });
                }
            }.worker, .{ hostname, &client, &wg });
        }
        wg.wait();

        std.time.sleep(std.time.ns_per_s);
    }
}
