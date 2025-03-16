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
const COLORS = [_]vaxis.Color{
    .{ .rgb = .{ 255, 255, 0 } },
    .{ .rgb = .{ 255, 0, 255 } },
    .{ .rgb = .{ 0, 255, 255 } },
    .{ .rgb = .{ 50, 150, 200 } },
    .{ .rgb = .{ 100, 200, 100 } },
    .{ .rgb = .{ 255, 0, 0 } },
    .{ .rgb = .{ 0, 255, 0 } },
    .{ .rgb = .{ 0, 0, 255 } },
    .{ .rgb = .{ 255, 165, 0 } },
    .{ .rgb = .{ 128, 0, 128 } },
};

pub const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    hostnames: [][]const u8,
    crawler_running: std.atomic.Value(bool),
    ts: ts.TimeSeries,

    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    statuses: std.ArrayList([]u8),
    minMsg: ?[]const u8 = null,
    maxMsg: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, hostnames: [][]const u8) !App {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .hostnames = hostnames,
            .crawler_running = std.atomic.Value(bool).init(true),
            .ts = try ts.TimeSeries.init(allocator),
            .statuses = std.ArrayList([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *App) void {
        self.ts.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();

        if (self.minMsg) |msg| {
            self.allocator.free(msg);
        }
        if (self.maxMsg) |msg| {
            self.allocator.free(msg);
        }

        for (self.statuses.items) |item| {
            self.allocator.free(item);
        }
        self.statuses.deinit();
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
            drawErr(container);
            return;
        }
        if (win.height < minHeight) {
            drawErr(container);
            return;
        }

        try self.drawSummary(container);

        const graphStartCol = try self.drawLegend(win, container);

        try self.drawGraph(win, container, graphStartCol);
    }

    fn drawErr(container: vaxis.Window) void {
        _ = container.printSegment(.{ .text = smallScreenErr, .style = .{ .fg = COLORS[1] } }, .{
            .row_offset = 1,
            .col_offset = 1,
        });
    }

    fn drawSummary(self: *App, container: vaxis.Window) !void {
        for (self.statuses.items) |msg| {
            self.allocator.free(msg);
        }
        self.statuses.clearRetainingCapacity();

        for (self.hostnames, 0..) |hostname, i| {
            var hostname_stats = self.ts.hostnamesStats.get(hostname);
            if (hostname_stats) |*stats| {
                const msg = try std.fmt.allocPrint(self.allocator, "{s}: avg {d:.1}ms, min {d}ms, max {d}ms", .{ hostname, stats.avg_latency, stats.min_latency, stats.max_latency });
                try self.statuses.append(msg);

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

    fn drawLegend(self: *App, win: vaxis.Window, container: vaxis.Window) !u16 {
        // Deallocate old legend
        if (self.minMsg) |msg| {
            self.allocator.free(msg);
        }
        if (self.maxMsg) |msg| {
            self.allocator.free(msg);
        }

        self.minMsg = try std.fmt.allocPrint(self.allocator, "{d}ms", .{self.ts.min_latency});
        self.maxMsg = try std.fmt.allocPrint(self.allocator, "{d}ms", .{self.ts.max_latency});

        var maxLen: usize = 0;

        if (self.minMsg) |minMsg| {
            maxLen = minMsg.len;
        }

        if (self.maxMsg) |maxMsg| {
            if (maxMsg.len > maxLen) {
                maxLen = maxMsg.len;
            }
        }

        // draw legend
        var row: u16 = @intCast(self.hostnames.len);
        row += 1;
        const verticalCol: u16 = @intCast(maxLen);
        while (row < win.height - 2) {
            _ = container.printSegment(.{
                .text = "│",
                .style = .{ .fg = COLORS[4] },
            }, .{
                .row_offset = row,
                .col_offset = verticalCol + 2,
            });
            row += 1;
        }

        if (self.minMsg) |minMsg| {
            const startRow: u16 = @intCast(self.hostnames.len);
            _ = container.printSegment(.{
                .text = minMsg,
                .style = .{ .fg = COLORS[3] },
            }, .{
                .row_offset = win.height - 3,
                .col_offset = 1,
            });
            if (self.maxMsg) |maxMsg| {
                _ = container.printSegment(.{
                    .text = maxMsg,
                    .style = .{ .fg = COLORS[3] },
                }, .{
                    .row_offset = startRow + 1,
                    .col_offset = 1,
                });
            }
        }

        return verticalCol + 2;
    }

    fn drawGraph(self: *App, win: vaxis.Window, container: vaxis.Window, graphStartCol: u16) !void {
        const graphStartRow: u16 = @intCast(self.hostnames.len + 1);
        const intervalsCount: usize = @intCast(win.width - graphStartCol - 1);
        const intervals = self.ts.getLastNIntervals(intervalsCount);

        var col_index: u16 = 0;
        while (col_index < intervals.len) {
            const results = intervals[col_index].crawl_results;
            for (self.hostnames, 0..) |hostname, i| {
                for (results) |result| {
                    if (std.mem.eql(u8, result.hostname, hostname)) {
                        const color_index = i % COLORS.len;
                        const color = COLORS[color_index];
                        const row_offset = self.latencyRowIndex(result.latency_ms, win.height - graphStartRow - 2);

                        _ = container.printSegment(.{
                            .text = "•",
                            .style = .{ .fg = color },
                        }, .{
                            .row_offset = row_offset + graphStartRow,
                            .col_offset = col_index + graphStartCol + 1,
                        });
                    }
                }
            }

            col_index += 1;
        }
    }

    fn latencyRowIndex(self: *App, latency: i32, rows: u16) u16 {
        if (self.ts.min_latency == self.ts.max_latency) {
            return 0;
        }
        if (latency < self.ts.min_latency) {
            return 0;
        }
        if (latency > self.ts.max_latency) {
            return 0;
        }

        const diff: f64 = @floatFromInt(latency - self.ts.min_latency);
        const total: f64 = @floatFromInt(self.ts.max_latency - self.ts.min_latency);
        const normalized: f64 = diff / total;
        const inverted: f64 = 1.0 - normalized;
        const rowsFloat: f64 = @floatFromInt(rows - 1);
        const rowIndex: u16 = @intFromFloat(inverted * rowsFloat);

        return rowIndex;
    }
};
