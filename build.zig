const std = @import("std");

pub fn build(b: *std.Build) void {
    const vaxis_dep = b.dependency("vaxis", .{
        .target = b.graph.host,
    });

    const exe = b.addExecutable(.{
        .name = "ztop",
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
