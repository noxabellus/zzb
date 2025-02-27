//! # zzb
//!
//! Zig Zon Builder is a simple utility that parses your `build.zig.zon` file, then
//! creates build steps and exports for you. It is designed to grow with your
//! project and therefore also provides a programmatic API.
//!
//! The purely declarative style of build is convenient for projects that have
//! relatively straight forward build workflows, in terms of meta-actions that need
//! to be performed, independent of project size. Projects where the overhead of
//! manually specifying everything imperatively is not necessary, but the loss of
//! path traceability with file-system scanning alternatives is undesirable. If
//! complications (inevitably?) creep in, you can easily transition to the
//! programmatic API to cut holes for those. If things end up getting really
//! complicated, you can phase it out and contend with very minimal,
//! straight-forward criteria for backwards compatibility.

const Builder = @This();

const std = @import("std");

const Manifest = struct { zzb_config: Config };
const BUILD_ZON = "./build.zig.zon";
const ZON_CONFIG = std.zon.parse.Options{
    .ignore_unknown_fields = true,
    .free_on_error = false,
};

/// Runs the build process based on a configuration encoded in the build.zig.zon file.
///
/// See `runConfig`.
pub fn run(zigBuild: *std.Build) !void {
    const configText = try std.fs.cwd().readFileAllocOptions(
        zigBuild.allocator,
        BUILD_ZON,
        std.math.maxInt(usize),
        1024,
        1,
        0,
    );

    var status = std.zon.parse.Status{};

    const zonParse = std.zon.parse.fromSlice(
        Manifest,
        zigBuild.allocator,
        configText,
        &status,
        ZON_CONFIG,
    );

    if (zonParse) |manifest| {
        return runConfig(zigBuild, manifest.zzb_config);
    } else |zonErr| {
        var errors = status.iterateErrors();
        while (errors.next()) |err| {
            const loc = err.getLocation(&status);
            const msg = err.fmtMessage(&status);

            std.debug.print(
                "ERROR [" ++ BUILD_ZON ++ ":{}:{}]: {}\n",
                .{ loc.line + 1, loc.column + 1, msg },
            );

            var notes = err.iterateNotes(&status);
            while (notes.next()) |note| {
                const note_loc = note.getLocation(&status);
                const note_msg = note.fmtMessage(&status);

                std.debug.print("NOTE [" ++ BUILD_ZON ++ ":{}:{}]: {s}\n", .{
                    note_loc.line + 1,
                    note_loc.column + 1,
                    note_msg,
                });
            }
        }

        return zonErr;
    }
}

/// Runs the build process based on the provided configuration.
///
/// This function sets up the build steps, adds dependencies, and configures the build process
/// for packages, modules, and binaries.
///
/// See `run`.
pub fn runConfig(owner: *std.Build, config: Config) !void {
    var b = Builder.init(owner);

    const installStep = owner.default_step;
    const checkStep = owner.step("check", "Run semantic analysis");
    const testStep = owner.step("test", "Run unit tests");

    for (config.packages) |pkg| {
        const pkgDependency = owner.dependency(pkg.name, .{ .target = b.target, .optimize = b.optimize });

        try b.package_map.put(pkg.alias orelse pkg.name, .{ pkg, pkgDependency });
    }

    for (config.modules) |mod| {
        const modPathStr = b.fmt("{s}/{s}.zig", .{ config.mod_path, mod.path orelse mod.name });
        const modPath = b.path(modPathStr);

        const moduleStandard = owner.createModule(.{
            .root_source_file = modPath,
            .target = b.target,
            .optimize = b.optimize,
        });

        const moduleTest = owner.addTest(.{
            .name = b.fmt("{s}-test", .{mod.name}),
            .root_source_file = modPath,
            .target = b.target,
            .optimize = b.optimize,
        });

        if (mod.exported) {
            try owner.modules.put(mod.name, moduleStandard);
        }

        try b.module_map.put(mod.name, moduleStandard);
        try b.test_map.put(mod.name, moduleTest.root_module);

        const runTest = owner.addRunArtifact(moduleTest);
        const unitTestStep = owner.step(b.fmt("test-{s}", .{mod.name}), b.fmt("Run unit tests for the {s} module", .{mod.name}));
        const unitCheckStep = owner.step(b.fmt("check-{s}", .{mod.name}), b.fmt("Run semantic analysis for the {s} module", .{mod.name}));

        checkStep.dependOn(&moduleTest.step);
        unitCheckStep.dependOn(&moduleTest.step);
        testStep.dependOn(&runTest.step);
        unitTestStep.dependOn(&runTest.step);
    }

    for (config.modules) |mod| {
        const moduleStandard = b.module_map.get(mod.name).?;
        b.addDependencies(.standard, moduleStandard, mod.dependencies);

        const moduleTest = b.test_map.get(mod.name).?;
        b.addDependencies(.testing, moduleTest, mod.dependencies);
    }

    for (config.binaries) |bin| {
        const binPathStr = b.fmt("{s}/{s}.zig", .{ config.bin_path, bin.path orelse bin.name });
        const binPath = b.path(binPathStr);

        const binaryStandard = owner.addExecutable(.{
            .name = bin.name,
            .root_source_file = binPath,
            .target = b.target,
            .optimize = b.optimize,
        });

        const binaryTest = owner.addTest(.{
            .name = b.fmt("{s}-test", .{bin.name}),
            .root_source_file = binPath,
            .target = b.target,
            .optimize = b.optimize,
        });

        b.addDependencies(.standard, binaryStandard.root_module, bin.dependencies);
        b.addDependencies(.testing, binaryTest.root_module, bin.dependencies);

        const runner = owner.addRunArtifact(binaryStandard);
        const installBinary = owner.addInstallArtifact(binaryStandard, .{});

        const runStep = owner.step(b.fmt("run-{s}", .{bin.name}), b.fmt("Build & run the {s} binary", .{bin.name}));
        const unitInstallStep = owner.step(bin.name, b.fmt("Build the {s} binary", .{bin.name}));
        const unitCheckStep = owner.step(b.fmt("check-{s}", .{bin.name}), b.fmt("Run semantic analysis for the {s} binary", .{bin.name}));
        const unitTestStep = owner.step(b.fmt("test-{s}", .{bin.name}), b.fmt("Run unit tests for the {s} binary", .{bin.name}));

        const runTest = owner.addRunArtifact(binaryTest);

        installStep.dependOn(&installBinary.step);
        unitInstallStep.dependOn(&installBinary.step);

        runStep.dependOn(&runner.step);

        checkStep.dependOn(&binaryTest.step);
        unitCheckStep.dependOn(&binaryTest.step);

        testStep.dependOn(&runTest.step);
        unitTestStep.dependOn(&runTest.step);
    }
}

/// Configuration for `run`.
pub const Config = struct {
    /// Provide the path to the modules directory.
    mod_path: [:0]const u8,
    /// Provide the path to the binaries directory.
    bin_path: [:0]const u8,
    /// Describe project dependencies.
    packages: []const Package,
    /// Describe all modules in the project.
    modules: []const Module,
    /// Describe all binaries in the project.
    binaries: []const Binary,
};

/// Represents a package with its name and alias.
pub const Package = struct {
    /// The name of the package.
    name: [:0]const u8,
    /// An optional alias for the package.
    alias: ?[:0]const u8,
};

/// Represents a module with its name, path, and dependencies.
pub const Module = struct {
    /// The name of the module.
    name: [:0]const u8,
    /// An optional path for the module.
    path: ?[:0]const u8 = null,
    /// Indicates whether the module is exported.
    exported: bool = true,
    /// An array of dependencies for the module.
    dependencies: []const Dependency = &.{},
};

/// Represents a binary with its name, path, and dependencies.
pub const Binary = struct {
    /// The name of the binary.
    name: [:0]const u8,
    /// An optional path for the binary.
    path: ?[:0]const u8 = null,
    /// An array of dependencies for the binary.
    dependencies: []const Dependency = &.{},
};

/// Represents a dependency, which can be an external or internal module.
pub const Dependency = union(enum) {
    /// Represents an external module dependency.
    external: External,
    /// Represents an internal module dependency.
    internal: [:0]const u8,

    /// Creates an external module dependency.
    pub fn ext(pkgName: [:0]const u8, modName: ?[:0]const u8) Dependency {
        return .{ .external = .{ .package_name = pkgName, .module_name = modName } };
    }

    /// Creates an internal module dependency.
    pub fn int(modName: [:0]const u8) Dependency {
        return .{ .internal = modName };
    }
};

/// Represents an external dependency, inside `Dependency`.
pub const External = struct {
    /// The name of the package.
    package_name: [:0]const u8,
    /// An optional name for the module.
    module_name: ?[:0]const u8 = null,
};

/// Build script that is using zzb.
owner: *std.Build,
/// The target for the build.
target: std.Build.ResolvedTarget,
/// The optimization mode for the build.
optimize: std.builtin.OptimizeMode,
/// A map of packages to their dependencies.
package_map: std.StringHashMap(struct { Package, *std.Build.Dependency }),
/// A map of modules to their standard build objects.
module_map: std.StringHashMap(*std.Build.Module),
/// A map of modules to their test build objects.
test_map: std.StringHashMap(*std.Build.Module),

fn init(b: *std.Build) Builder {
    return Builder{
        .owner = b,

        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),

        .package_map = std.StringHashMap(struct { Package, *std.Build.Dependency }).init(b.allocator),
        .module_map = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .test_map = std.StringHashMap(*std.Build.Module).init(b.allocator),
    };
}

fn addDependencies(self: *Builder, mode: enum { standard, testing }, module: *std.Build.Module, dependencies: []const Dependency) void {
    const internals = switch (mode) {
        .standard => &self.module_map,
        .testing => &self.test_map,
    };

    for (dependencies) |depUnion| {
        switch (depUnion) {
            .external => |dep| {
                const pkg, const package = self.package_map.get(dep.package_name) orelse @panic(self.fmt("package not found: {s}", .{dep.package_name}));
                const dependencyName =
                    if (dep.module_name) |modName| self.owner.fmt("{s}/{s}", .{ dep.package_name, modName }) else dep.package_name;

                module.addImport(dependencyName, package.module(dep.module_name orelse pkg.name));
            },
            .internal => |module_name| {
                const dependency = internals.get(module_name) orelse @panic(self.fmt("module not found: {s}", .{module_name}));

                module.addImport(module_name, dependency);
            },
        }
    }
}

/// Formats a string using the build's allocator.
pub fn fmt(self: *Builder, comptime f: []const u8, as: anytype) []u8 {
    return self.owner.fmt(f, as);
}

/// Creates a lazy path using the build's allocator.
pub fn path(self: *Builder, p: []const u8) std.Build.LazyPath {
    return self.owner.path(p);
}
