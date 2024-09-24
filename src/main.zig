const std = @import("std");

const proc_path = "/proc/";

// TODO: Use a struct to represent the process and populate it
const Process = struct {
    pid: u32,
    command: []const u8,
};

fn readCmdLine(allocator: std.mem.Allocator, pid: u32, buffer: []u8) !usize {
    const path = try std.fmt.allocPrint(allocator, "{s}/{d}/cmdline", .{ proc_path, pid });
    var cmdline = try std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{});

    return try cmdline.readAll(buffer);
}

fn readComm(allocator: std.mem.Allocator, pid: u32, buffer: []u8) !usize {
    const path = try std.fmt.allocPrint(allocator, "{s}/{d}/comm", .{ proc_path, pid });
    var cmdline = try std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{});

    return try cmdline.readAll(buffer);
}

pub fn main() !void {
    // TODO: Consider using general purpose allocator when building the loop
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var proc_dir = try std.fs.openDirAbsolute(proc_path, std.fs.Dir.OpenDirOptions{ .iterate = true });
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    var buffer: [256]u8 = undefined;

    var process_list = std.ArrayList(Process).init(alloc);
    while (try iter.next()) |entry| {
        if (entry.kind != std.fs.File.Kind.directory) {
            continue;
        }
        const pid: u32 = std.fmt.parseInt(u32, entry.name, 10) catch continue;

        var read = try readCmdLine(alloc, pid, &buffer);
        if (read == 0) {
            read = try readComm(alloc, pid, &buffer);
            read = read - 1;
        }
        const exec = if (read > 0) try std.mem.Allocator.dupe(alloc, u8, buffer[0..read]) else "Unknown";
        try process_list.append(Process{ .pid = pid, .command = exec });
    }
    for (process_list.items) |p| {
        std.debug.print("{d}\t{s}\n", .{ p.pid, p.command });
    }
}
