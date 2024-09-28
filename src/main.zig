const std = @import("std");
const fs = std.fs;

const Process = struct {
    allocator: std.mem.Allocator,
    pid: u32,
    command: []const u8,
    status: Status,

    const Status = struct {
        allocator: std.mem.Allocator,
        state: []const u8,

        pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !Status {
            var buf_reader = std.io.bufferedReader(file.reader());
            var in_stream = buf_reader.reader();
            var buf: [1024]u8 = undefined;
            var state: []u8 = undefined;
            while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
                var it = std.mem.split(u8, line, ":\t");

                if (std.mem.eql(u8, it.first(), "State")) {
                    state = try std.mem.Allocator.dupe(allocator, u8, it.next().?);
                }
            }

            return .{
                .allocator = allocator,
                .state = state,
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, pid: u32, command: []const u8, status: Status) !Process {
        return .{
            .allocator = allocator,
            .pid = pid,
            .command = command,
            .status = status,
        };
    }

    pub fn deinit(self: Process) void {
        self.allocator.free(self.command);
        // TODO: move this to Process.Status
        self.allocator.free(self.status.state);
    }
};

const ProcessList = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Process),

    pub fn init(allocator: std.mem.Allocator) !ProcessList {
        return ProcessList{
            .allocator = allocator,
            .list = std.ArrayList(Process).init(allocator),
        };
    }

    pub fn deinit(self: ProcessList) void {
        for (self.list.items) |p| {
            p.deinit();
        }
        self.list.deinit();
    }
};

const ProcReader = struct {
    allocator: std.mem.Allocator,
    proc_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, proc_path: []const u8) !ProcReader {
        return ProcReader{
            .proc_path = proc_path,
            .allocator = allocator,
        };
    }

    fn readCmdLine(self: ProcReader, proc_dir: fs.Dir, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{d}/cmdline", .{pid});
        defer self.allocator.free(path);

        var cmdline = try proc_dir.openFile(path, .{});
        defer cmdline.close();

        return try cmdline.readAll(buffer);
    }

    fn readComm(self: ProcReader, proc_dir: fs.Dir, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{d}/comm", .{pid});
        defer self.allocator.free(path);

        var cmdline = try proc_dir.openFile(path, .{});
        defer cmdline.close();

        return try cmdline.readAll(buffer);
    }

    fn readCommand(self: ProcReader, proc_dir: fs.Dir, pid: u32) ![]u8 {
        var buffer: [256]u8 = undefined;
        var read = try self.readCmdLine(proc_dir, pid, &buffer);
        if (read == 0) {
            read = try self.readComm(proc_dir, pid, &buffer);
            read = read - 1;
        }
        if (read <= 0) {
            return error.UnknownCommand;
        }
        return try std.mem.Allocator.dupe(self.allocator, u8, buffer[0..read]);
    }

    fn readStatus(self: ProcReader, proc_dir: fs.Dir, pid: u32) !Process.Status {
        const path = try std.fmt.allocPrint(self.allocator, "{d}/status", .{pid});
        defer self.allocator.free(path);

        var status_file = try proc_dir.openFile(path, .{});
        defer status_file.close();
        return try Process.Status.init(self.allocator, status_file);
    }

    pub fn readProcesses(self: ProcReader) !ProcessList {
        var proc_dir = try fs.openDirAbsolute(self.proc_path, std.fs.Dir.OpenDirOptions{ .iterate = true });
        defer proc_dir.close();

        var iter = proc_dir.iterate();
        var process_list = try ProcessList.init(self.allocator);
        errdefer process_list.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != fs.File.Kind.directory) {
                continue;
            }
            const pid: u32 = std.fmt.parseInt(u32, entry.name, 10) catch continue;
            const exec = self.readCommand(proc_dir, pid) catch "Unknown";
            const status = try self.readStatus(proc_dir, pid);
            try process_list.list.append(try Process.init(self.allocator, pid, exec, status));
        }
        return process_list;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const proc_reader = try ProcReader.init(alloc, "/proc/");

    const process_list = try proc_reader.readProcesses();
    defer process_list.deinit();

    std.debug.print("PID\tSTATE\tCMD\n", .{});
    for (process_list.list.items) |p| {
        std.debug.print("{d}\t{s}\t{s}\n", .{ p.pid, p.status.state, p.command });
    }
}
