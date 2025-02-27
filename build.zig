/// The Builder is the main entry point for the zzb package
pub const Builder = @import("src/zzb.zig");

/// This is the zzb package build script; you can ignore this function
pub fn build(b: *@import("std").Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const m = b.addModule("zzb", .{
        .root_source_file = b.path("src/zzb.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = m;

    const checkTest = b.addTest(.{
        .name = "zzb",
        .root_source_file = b.path("src/zzb.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.step("check", "Run semantic analysis").dependOn(&checkTest.step);
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(checkTest).step);
}
