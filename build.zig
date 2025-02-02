const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("bencode", .{
        .root_source_file = b.path("src/bencode.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("src/bencode.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
