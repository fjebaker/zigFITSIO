const std = @import("std");
const zlib = @import("./vendor/zig-zlib/zlib.zig");
const libcurl = @import("./vendor/zig-libcurl/libcurl.zig");

fn _root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse ".");
}

pub const ROOT = _root() ++ "/";
pub const CFITS_DIR = ROOT ++ "vendor/cfitsio-4.0.0/";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libcfitsio = createCFITSIO(b, target);
    libcfitsio.installHeader(CFITS_DIR ++ "fitsio.h", "fitsio.h");

    b.installArtifact(libcfitsio);

    _ = b.addModule("zfits", .{
        .source_file = .{ .path = "./src/main.zig" },
        .dependencies = &.{},
    });
    // todo: https://github.com/ziglang/zig/pull/14731

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "./src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.linkLibC();
    main_tests.linkLibrary(libcfitsio);
    const main_test_runstep = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_test_runstep.step);
}

pub fn createCFITSIO(b: *std.Build, target: std.zig.CrossTarget) *std.build.CompileStep {
    const lib = b.addStaticLibrary(.{
        .name = "cfitsio",
        .target = target,
        .optimize = .ReleaseSafe,
    });

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

    const cflags = switch (target.getOsTag()) {
        .macos => [2][]const u8{ "-O2", "-Dmacintosh" },
        else => [2][]const u8{ "-O2", "-Dg77Fortran" },
    };

    inline for (sources) |f| {
        lib.addCSourceFile(CFITS_DIR ++ f, &cflags);
    }
    lib.linkLibC();

    const z = zlib.create(b, target, .ReleaseSafe);
    z.link(lib, .{});

    const curl = zlib.create(b, target, .ReleaseSafe);
    curl.link(lib, .{});
    return lib;
}
