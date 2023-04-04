const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    lib: *std.build.Module,
    cfitslib: *std.build.CompileStep,
    inc_path: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = "zfts",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "zfts/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const clapmod = b.addModule("clap", .{
        .source_file = .{ .path = "vendor/zig-clap/clap.zig" },
        .dependencies = &.{},
    });
    const ansimod = b.addModule("ansi", .{
        .source_file = .{ .path = "vendor/zig-ansi/src/lib.zig" },
        .dependencies = &.{},
    });

    exe.addModule("clap", clapmod);
    exe.addModule("ansi", ansimod);
    exe.addModule("zfits", lib);
    exe.linkLibC();
    exe.linkLibrary(cfitslib);
    exe.addIncludePath(inc_path);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    exe.install();

    // This *creates* a RunStep in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = exe.run();

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing.
    // const exe_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // // Similar to creating the run step earlier, this exposes a `test` step to
    // // the `zig build --help` menu, providing a way for the user to request
    // // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&exe_tests.step);
}