const std = @import("std");

const Process = struct {
    allocator: std.mem.Allocator,
    pid: u32,
    command: []const u8,

    pub fn init(allocator: std.mem.Allocator, pid: u32, command: []const u8) !Process {
        return .{
            .allocator = allocator,
            .pid = pid,
            .command = command,
        };
    }

    pub fn deinit(self: Process) void {
        self.allocator.free(self.command);
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

    fn readCmdLine(self: ProcReader, proc_dir: std.fs.Dir, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{d}/cmdline", .{pid});
        defer self.allocator.free(path);

        var cmdline = try proc_dir.openFile(path, .{});

        return try cmdline.readAll(buffer);
    }

    fn readComm(self: ProcReader, proc_dir: std.fs.Dir, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{d}/comm", .{pid});
        defer self.allocator.free(path);

        var cmdline = try proc_dir.openFile(path, .{});

        return try cmdline.readAll(buffer);
    }

    fn readCommand(self: ProcReader, proc_dir: std.fs.Dir, pid: u32) ![]u8 {
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

    pub fn readProcesses(self: ProcReader) !ProcessList {
        var proc_dir = try std.fs.openDirAbsolute(self.proc_path, std.fs.Dir.OpenDirOptions{ .iterate = true });
        defer proc_dir.close();

        var iter = proc_dir.iterate();
        var process_list = try ProcessList.init(self.allocator);
        errdefer process_list.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != std.fs.File.Kind.directory) {
                continue;
            }
            const pid: u32 = std.fmt.parseInt(u32, entry.name, 10) catch continue;
            const exec = self.readCommand(proc_dir, pid) catch "Unknown";
            try process_list.list.append(try Process.init(self.allocator, pid, exec));
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

    for (process_list.list.items) |p| {
        std.debug.print("{d}\t{s}\n", .{ p.pid, p.command });
    }
}
