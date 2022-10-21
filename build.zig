const std = @import("std");

const CFITS_DIR = "./vendor/cfitsio-4.0.0/";

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const libcfitsio = try createCFITSIO(b, target);
    libcfitsio.install();

    const lib = b.addStaticLibrary("zfits", "src/main.zig");
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.linkLibrary(libcfitsio);
    lib.addIncludePath(CFITS_DIR);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.linkLibC();
    main_tests.linkLibrary(libcfitsio);
    main_tests.addIncludePath(CFITS_DIR);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

pub fn createCFITSIO(b: *std.build.Builder, target: std.zig.CrossTarget) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("cfitsio", null);
    lib.setBuildMode(.ReleaseSafe);
    lib.setTarget(target);

    const sources = [_][]const u8{
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

    const cflags = [_][]const u8{ "-O2", "-Wl", "-Dg77Fortran" };
    inline for (sources) |f| {
        lib.addCSourceFile(CFITS_DIR ++ f, &cflags);
    }
    lib.linkLibC();
    lib.linkSystemLibrary("zlib");
    lib.linkSystemLibrary("curl");
    return lib;
}
