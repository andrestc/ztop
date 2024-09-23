const std = @import("std");

const proc_path = "/proc/";

// TODO: Use a struct to represent the process and populate it
const Process = struct {
    Pid: []u8,
    Command: []u8,
};

fn readCmdLine(allocator: std.mem.Allocator, pid: []const u8, buffer: []u8) !usize {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}/cmdline", .{ proc_path, pid });
    var cmdline = try std.fs.openFileAbsolute(path, std.fs.File.OpenFlags{});

    return try cmdline.readAll(buffer);
}

fn readComm(allocator: std.mem.Allocator, pid: []const u8, buffer: []u8) !usize {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}/comm", .{ proc_path, pid });
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

    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                _ = std.fmt.parseInt(i32, entry.name, 10) catch continue;
            },
            else => continue,
        }

        var read = try readCmdLine(alloc, entry.name, &buffer);
        if (read == 0) {
            read = try readComm(alloc, entry.name, &buffer);
            read = read - 1;
        }
        const exec = if (read > 0) buffer[0..read] else "Unknown";
        std.debug.print("{s}\t{s}\n", .{ entry.name, exec });
    }
}
