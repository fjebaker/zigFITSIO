const std = @import("std");

fn _root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse ".");
}

const CFITSIO_SOURCES = [_][]const u8{
    "buffers.c",     "cfileio.c",        "checksum.c",         "drvrfile.c",  "drvrmem.c",
    "drvrnet.c",     "drvrsmem.c",       "editcol.c",          "edithdu.c",   "eval_l.c",
    "eval_y.c",      "eval_f.c",         "fitscore.c",         "getcol.c",    "getcolb.c",
    "getcold.c",     "getcole.c",        "getcoli.c",          "getcolj.c",   "getcolk.c",
    "getcoll.c",     "getcols.c",        "getcolsb.c",         "getcoluk.c",  "getcolui.c",
    "getcoluj.c",    "getkey.c",         "group.c",            "grparser.c",  "histo.c",
    "iraffits.c",    "modkey.c",         "putcol.c",           "putcolb.c",   "putcold.c",
    "putcole.c",     "putcoli.c",        "putcolj.c",          "putcolk.c",   "putcoluk.c",
    "putcoll.c",     "putcols.c",        "putcolsb.c",         "putcolu.c",   "putcolui.c",
    "putcoluj.c",    "putkey.c",         "region.c",           "scalnull.c",  "swapproc.c",
    "wcssub.c",      "wcsutil.c",        "imcompress.c",       "quantize.c",  "ricecomp.c",
    "pliocomp.c",    "fits_hcompress.c", "fits_hdecompress.c", "simplerng.c",
    // zlib sources
    "zcompress.c",
    "zuncompress.c",
    // fitsio src
    "f77_wrap1.c",      "f77_wrap2.c",        "f77_wrap3.c", "f77_wrap4.c",
};

const CFITSIO_HEADERS = [_][]const u8{
    "cfortran.h",
    "drvrgsiftp.h",
    "drvrsmem.h",
    "eval_defs.h",
    "eval_tab.h",
    "f77_wrap.h",
    "fitsio.h",
    "fitsio2.h",
    "fpack.h",
    "group.h",
    "grparser.h",
    "longnam.h",
    "region.h",
    "simplerng.h",
};

pub const ROOT = _root() ++ "/";
pub const CFITS_DIR = ROOT ++ "vendor/cfitsio-4.2.0/";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libcfitsio = createCFITSIO(b, target);
    b.installArtifact(libcfitsio);

    const mod = b.addModule("zfitsio", .{
        .root_source_file = .{ .path = "./src/main.zig" },
    });
    mod.addIncludePath(.{ .path = CFITS_DIR });

    // todo: https://github.com/ziglang/zig/pull/14731

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "./src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.root_module.addImport("zfitsio", mod);
    // main_tests.linkLibC();
    // main_tests.linkLibrary(libcfitsio);
    const main_test_runstep = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_test_runstep.step);
}

pub fn createCFITSIO(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "cfitsio",
        .target = target,
        .optimize = .ReleaseSafe,
    });
    // const lib = b.addSharedLibrary(.{
    //     .name = "cfitsio",
    //     .target = target,
    //     .optimize = .ReleaseSafe,
    //     .version = .{ .major = 0, .minor = 1 },
    // });

    const cflags = switch (target.result.os.tag) {
        .macos => [2][]const u8{ "-O2", "-Dmacintosh" },
        else => [2][]const u8{ "-O2", "-Dg77Fortran" },
    };

    inline for (CFITSIO_SOURCES) |f| {
        lib.addCSourceFile(.{ .file = .{ .path = CFITS_DIR ++ f }, .flags = &cflags });
    }
    lib.linkLibC();

    const zlib = b.dependency("zlib", .{ .target = target, .optimize = .ReleaseSafe });
    const z = zlib.artifact("z");
    lib.linkLibrary(z);

    inline for (CFITSIO_HEADERS) |header| {
        lib.installHeader(.{ .path = CFITS_DIR ++ header }, header);
    }

    return lib;
}
