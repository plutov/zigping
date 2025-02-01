const std = @import("std");
const vaxis = @import("vaxis");
const crawler = @import("crawler.zig");

pub const Event = union(enum) {
    winsize: vaxis.Winsize,
    key_press: vaxis.Key,
    crawl_result: crawler.CrawlResult,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    hostnames: [][]const u8,
    results: std.ArrayList(crawler.CrawlResult),
    crawler_running: std.atomic.Value(bool),

    tty: vaxis.Tty,
    vx: vaxis.Vaxis,

    pub fn init(allocator: std.mem.Allocator, hostnames: [][]const u8) !App {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .hostnames = hostnames,
            .results = std.ArrayList(crawler.CrawlResult).init(allocator),
            .crawler_running = std.atomic.Value(bool).init(true),
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.results.deinit();
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        defer loop.stop();

        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        // disable mouse
        try self.vx.setMouseMode(self.tty.anyWriter(), false);

        // run crawler in thread
        const crawler_thread = try std.Thread.spawn(.{}, struct {
            fn worker(_hostnames: [][]const u8, _allocator: std.mem.Allocator, _loop: *vaxis.Loop(Event), _crawler_running: *std.atomic.Value(bool)) !void {
                defer _crawler_running.store(false, std.builtin.AtomicOrder.release);
                try crawler.start(_hostnames, _allocator, _loop, _crawler_running);
            }
        }.worker, .{ self.hostnames, self.allocator, &loop, &self.crawler_running });

        // main event loop
        while (!self.should_quit) {
            const event = loop.nextEvent();
            try self.update(event);
            if (self.should_quit) {
                // stop the thread and wait for it to finish
                self.crawler_running.store(false, std.builtin.AtomicOrder.release);
                crawler_thread.join();
            }

            self.draw();

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
            .crawl_result => |result| {
                _ = try self.results.append(result);
            },
        }
    }

    pub fn draw(self: *App) void {
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

        _ = container.printSegment(.{ .text = "YO" }, .{});
        // const msg = std.fmt.allocPrint(self.allocator, "HI {d}", .{self.results.items.len}) catch {
        //     _ = win.printSegment(.{ .text = "ERROR" }, .{});
        //     return;
        // };
        // defer self.allocator.free(msg);
        // _ = container.printSegment(.{ .text = msg }, .{});
    }
};
