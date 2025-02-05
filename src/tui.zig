const std = @import("std");
const vaxis = @import("vaxis");
const crawler = @import("crawler.zig");
const ts = @import("ts.zig");

pub const Event = union(enum) {
    winsize: vaxis.Winsize,
    key_press: vaxis.Key,
    crawl_results: []const crawler.CrawlResult,
};

const minWidth: u16 = 50;
const minHeight: u16 = 25;
const smallScreenErr = "SCREEN IS TOO SMALL";

// collection of colors
const COLORS = [5]vaxis.Color{
    .{ .rgb = .{ 255, 255, 0 } },
    .{ .rgb = .{ 255, 0, 255 } },
    .{ .rgb = .{ 0, 255, 255 } },
    .{ .rgb = .{ 50, 150, 200 } },
    .{ .rgb = .{ 100, 200, 100 } },
};

pub const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    hostnames: [][]const u8,
    crawler_running: std.atomic.Value(bool),
    ts: ts.TimeSeries,

    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    state: struct {
        messages: std.ArrayList([]u8),
    },

    pub fn init(allocator: std.mem.Allocator, hostnames: [][]const u8) !App {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .hostnames = hostnames,
            .crawler_running = std.atomic.Value(bool).init(true),
            .ts = try ts.TimeSeries.init(allocator),
            .state = .{
                .messages = std.ArrayList([]u8).init(allocator),
            },
        };
    }

    pub fn deinit(self: *App) void {
        self.ts.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();

        for (self.state.messages.items) |item| {
            self.allocator.free(item);
        }
        self.state.messages.deinit();
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        defer loop.stop();

        var crawler_instance = crawler.Crawler.init(self.allocator);
        defer crawler_instance.deinit();

        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        // disable mouse
        try self.vx.setMouseMode(self.tty.anyWriter(), false);

        // run crawler in thread
        const crawler_thread = try std.Thread.spawn(.{ .allocator = self.allocator }, struct {
            fn worker(_hostnames: [][]const u8, _crawler_instance: *crawler.Crawler, _loop: *vaxis.Loop(Event), _crawler_running: *std.atomic.Value(bool)) !void {
                _crawler_instance.start(_hostnames, _loop, _crawler_running);
            }
        }.worker, .{ self.hostnames, &crawler_instance, &loop, &self.crawler_running });

        // main event loop
        while (!self.should_quit) {
            loop.pollEvent();
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            if (self.should_quit) {
                // stop the thread and wait for it to finish
                self.crawler_running.store(false, .release);
                crawler_thread.join();
                return;
            }

            try self.draw();
            try self.vx.render(self.tty.anyWriter());
        }
    }

    pub fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.should_quit = true;
                    return;
                }
                if (key.matches('q', .{})) {
                    self.should_quit = true;
                    return;
                }
            },
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
            },
            .crawl_results => |results| {
                try self.ts.addResults(results);
            },
        }
    }

    pub fn draw(self: *App) !void {
        const win = self.vx.window();

        win.clear();
        win.hideCursor();
        self.vx.setMouseShape(.default);

        const container = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = win.width,
            .height = win.height,
            .border = .{ .where = .all },
        });

        // terminate on small screens
        if (win.width < minWidth) {
            _ = win.printSegment(.{ .text = smallScreenErr, .style = .{ .fg = COLORS[1] } }, .{
                .row_offset = 1,
                .col_offset = 1,
            });
            return;
        }
        if (win.height < minHeight) {
            _ = win.printSegment(.{ .text = smallScreenErr, .style = .{ .fg = COLORS[1] } }, .{
                .row_offset = 1,
                .col_offset = 1,
            });
            return;
        }

        for (self.hostnames, 0..) |hostname, i| {
            var hostname_stats = self.ts.hostnamesStats.get(hostname);
            if (hostname_stats) |*stats| {
                const msg = try std.fmt.allocPrint(self.allocator, "{s}: avg {d:.2}ms, min {d:.2}ms, max {d:.2}ms", .{ hostname, stats.avg_latency, stats.min_latency, stats.max_latency });
                try self.state.messages.append(msg);

                const color_index = i % COLORS.len;
                const color = COLORS[color_index];

                // print hostname line
                const row: u16 = @intCast(i);
                _ = container.printSegment(.{
                    .text = msg,
                    .style = .{ .fg = color },
                }, .{
                    .row_offset = row,
                    .col_offset = 1,
                });
            }
        }
    }
};
