const std = @import("std");

const Process = struct {
    pid: u32,
    command: []const u8,
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
        defer self.list.deinit();
        for (self.list.items) |p| {
            self.allocator.free(p.command);
        }
    }
};

const ProcReader = struct {
    allocator: std.mem.Allocator,
    proc_path: []const u8,
    proc_dir: *std.fs.Dir,

    pub fn init(allocator: std.mem.Allocator, proc_path: []const u8) !ProcReader {
        var proc_dir = try std.fs.openDirAbsolute(proc_path, std.fs.Dir.OpenDirOptions{ .iterate = true });
        return ProcReader{
            .proc_path = proc_path,
            .allocator = allocator,
            .proc_dir = &proc_dir,
        };
    }

    pub fn deinit(self: ProcReader) void {
        self.proc_dir.close();
    }

    fn readCmdLine(self: ProcReader, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{d}/cmdline", .{ self.proc_path, pid });
        defer self.allocator.free(path);

        var cmdline = try std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{});
        return try cmdline.readAll(buffer);
    }

    fn readComm(self: ProcReader, pid: u32, buffer: []u8) !usize {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{d}/comm", .{ self.proc_path, pid });
        defer self.allocator.free(path);

        var cmdline = try std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{});

        return try cmdline.readAll(buffer);
    }

    fn readCommand(self: ProcReader, pid: u32) ![]u8 {
        var buffer: [256]u8 = undefined;
        var read = try self.readCmdLine(pid, &buffer);
        if (read == 0) {
            read = try self.readComm(pid, &buffer);
            read = read - 1;
        }
        if (read <= 0) {
            return error.UnknownCommand;
        }
        return try std.mem.Allocator.dupe(self.allocator, u8, buffer[0..read]);
    }

    pub fn readProcesses(self: ProcReader) !ProcessList {
        var iter = self.proc_dir.iterate();
        var process_list = try ProcessList.init(self.allocator);
        while (try iter.next()) |entry| {
            if (entry.kind != std.fs.File.Kind.directory) {
                continue;
            }
            const pid: u32 = std.fmt.parseInt(u32, entry.name, 10) catch continue;
            const exec = self.readCommand(pid) catch "Unknown";
            try process_list.list.append(Process{ .pid = pid, .command = exec });
        }
        return process_list;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const proc_reader = try ProcReader.init(alloc, "/proc/");
    defer proc_reader.deinit();

    const process_list = try proc_reader.readProcesses();
    defer process_list.deinit();

    for (process_list.list.items) |p| {
        std.debug.print("{d}\t{s}\n", .{ p.pid, p.command });
    }
}
