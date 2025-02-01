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

    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    loop: vaxis.Loop(Event),
    win_ready: bool,

    pub fn init(allocator: std.mem.Allocator, hostnames: [][]const u8) !App {
        var tty = try vaxis.Tty.init();
        var vx = try vaxis.init(allocator, .{});

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = tty,
            .vx = vx,
            .hostnames = hostnames,
            .results = std.ArrayList(crawler.CrawlResult).init(allocator),
            .loop = .{
                .tty = &tty,
                .vaxis = &vx,
            },
            .win_ready = false,
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *App) !void {
        try self.loop.init();
        try self.loop.start();
        defer self.loop.stop();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        // disable mouse
        try self.vx.setMouseMode(self.tty.anyWriter(), false);

        // run crawler in thread
        _ = try std.Thread.spawn(.{}, struct {
            fn worker(_hostnames: [][]const u8, _allocator: std.mem.Allocator, _loop: *vaxis.Loop(Event)) !void {
                try crawler.start(_hostnames, _allocator, _loop);
            }
        }.worker, .{ self.hostnames, self.allocator, &self.loop });

        // main event loop
        while (!self.should_quit) {
            const event = self.loop.nextEvent();
            try self.update(event);

            self.draw();

            var buffered = self.tty.bufferedWriter();

            // render the application to the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
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
                self.win_ready = true;
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

        if (!self.win_ready) {
            return;
        }

        const container = win.child(.{
            .x_off = 1,
            .y_off = 1,
            .width = win.width - 2,
            .height = win.height - 2,
            // todo: add border
            .border = .{ .where = .all },
        });

        const msg = std.fmt.allocPrint(self.allocator, "HI {d}", .{self.results.items.len}) catch {
            _ = win.printSegment(.{ .text = "ERROR" }, .{});
            return;
        };
        defer self.allocator.free(msg);
        _ = container.printSegment(.{ .text = msg }, .{});
    }
};
