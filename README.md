# zzb

Zig Zon Builder is a simple utility that parses your `build.zig.zon` file, then
creates build steps and such for you. It is designed to grow with your project
and therefore also provides a programmatic API.

The purely declarative style of build is convenient for projects that have
relatively straight forward build workflows, in terms of meta-actions that need
to be performed, independent of project size. Projects where the overhead of
manually specifying everything imperatively is not necessary, but the loss of
path traceability with file-system scanning alternatives is undesirable. If
complications (inevitably?) creep in, you can easily transition to the
programmatic API to cut holes for those. If things end up getting really
complicated, you can phase it out and contend with very minimal,
straight-forward criteria for backwards compatibility.

## Usage

Zig doc available at [noxabell.us/zzb](https://noxabell.us/zzb).

You can also generate it with `zig build-lib -femit-docs -fno-emit-bin src/zzb.zig`.

Once setup, a set of build steps are made available:
```sh
# default (install) step
zig build

# run steps for binaries: `run-[NAME]`
zig build run-main

# total-project test step
zig build test

# specific module and binary test steps as well: `test-[NAME]`
zig build test-main

# total-project check step for use with zls
zig build check

# specific module and binary check steps as well: `check-[NAME]`
zig build check-main

# flags work as expected
zig build run-main --release=fast
```

`build.zig`:
```zig
pub const build = @import("zzb").Builder.run;
```

`build.zig.zon`:
```zig
.{
    .name = "cool_zig_package",
    .version = "0.1.0",
    .minimum_zig_version = "0.14.0-dev.3367+1cc388d52",
    .dependencies = .{
        .zzb = .{
            .url = "https://github.com/noxabellus/zzb#COMMIT_HASH_HERE",
            .hash = "...",
        },
        .example_dep = .{
            .url = "https://example.com/foo.tar.gz",
            .hash = "...",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "LICENSE",
        "README.md",
    },

    .zzb_config = .{
        .mod_path = "src/mod",
        .bin_path = "src/bin",
        .packages = .{
            .{
                .name = "example_dep",
                .alias = "example",
            },
        },
        .modules = .{
            .{
                .name = "foo",
                .exported = false,
            },
            .{
                .name = "X",
                .dependencies = .{
                    .{ .internal = "foo" },
                },
            },
        },
        .binaries = .{
            .{
                .name = "main",
                .dependencies = .{
                    .{ .internal = "X" },
                    .{ .external = .{
                        .package_name = "example",
                        .module_name = "ExampleModule",
                    } },
                },
            },
        },
    },
}
```

Usage from the `build.zig` of a package that depends on yours is typical:
```zig
const cool_zig_package = b.dependency("cool_zig_package", .{
    .target = ourTarget,
    .optimize = ourOptimize,
});

// 👎 not exported
b.module("foo");

// 👍 modules exported by default
const X = b.module("X");
```

## 📋 Todo
- [x] Creation and linking of zig modules
- [x] Run steps for binaries
- [x] Check steps for zls
- [x] Default (install) step
- [x] Test steps
- [ ] Improve programmatic api
- [ ] Config generation
- [ ] Static libraries
- [ ] Shared libraries
- [ ] Arbitrary artifacts
