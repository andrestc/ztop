const std = @import("std");
const vaxis = @import("vaxis");
const proc = @import("proc.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const App = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,

    proc_reader: proc.ProcReader,

    pub fn init(allocator: std.mem.Allocator) !App {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .proc_reader = try proc.ProcReader.init(allocator, "/proc/"),
        };
    }

    pub fn deinit(self: *App) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.arena.deinit();
    }

    fn update(self: *App, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{})) {
                    self.should_quit = true;
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
        }
    }

    pub fn run(self: *App) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();

        try loop.start();

        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        while (!self.should_quit) {
            loop.pollEvent();

            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            const process_list = try self.proc_reader.readProcesses();
            defer process_list.deinit();

            try self.draw(process_list);

            // It's best to use a buffered writer for the render method. TTY provides one, but you
            // may use your own. The provided bufferedWriter has a buffer size of 4096
            var buffered = self.tty.bufferedWriter();
            // Render the application to the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    fn draw(self: *App, process_list: proc.ProcessList) !void {
        if (!self.arena.reset(std.heap.ArenaAllocator.ResetMode.retain_capacity)) {
            return error.ArenaResetFail;
        }
        // TODO: handle columns better and spacing between header & body
        const columns = "PID    STATE   CMD";

        const win = self.vx.window();

        win.clear();

        self.vx.setMouseShape(.default);

        const header = win.child(.{
            .x_off = 5,
            .y_off = 0,
            .width = .{ .limit = columns.len },
            .height = .{ .limit = 1 },
        });

        const body = win.child(.{
            .x_off = 5,
            .y_off = 1,
            .width = .{ .limit = 120 },
            .height = .{ .limit = 40 },
        });

        // TODO: support scrolling thru the list of processes.
        // Maybe an event + storing offset?

        _ = try header.printSegment(.{ .text = columns, .style = .{} }, .{});
        for (0.., process_list.list.items) |row, p| {
            const text = try std.fmt.allocPrint(self.arena.allocator(), "{d}    {s}    {s}", .{ p.pid, p.status.state, p.command });
            _ = try body.printSegment(.{ .text = text }, .{ .row_offset = row });
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    var app = try App.init(alloc);
    defer app.deinit();

    try app.run();
}
