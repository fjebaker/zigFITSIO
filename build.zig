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
    lib.linkSystemLibrary("zlib");
    lib.linkSystemLibrary("libcurl");

    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

pub fn createCFITSIO(b: *std.build.Builder, target: std.zig.CrossTarget) !*std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("cfitsio", null);
    lib.setBuildMode(.ReleaseSafe);
    lib.setTarget(target);

    // const handle_with_care = [_][] const u8 {
    //     "f77_wrap1.c",
    //     "f77_wrap2.c",
    //     "f77_wrap3.c",
    //     "f77_wrap4.c",
    //     "swapproc.c",
    // };
    // const disclude = [_][] const u8 {
    //     "windumpexts.c",
    //     "vmieee.c",
    // };
    // var sources = std.ArrayList([]const u8).init(b.allocator);
    // // Search for all C/C++ files in `src` and add them
    // {
    //     var dir = try std.fs.cwd().openIterableDir(CFITS_DIR, .{});

    //     var walker = try dir.walk(b.allocator);
    //     defer walker.deinit();

    //     while (try walker.next()) |entry| {
    //         const ext = std.fs.path.extension(entry.basename);
    //         var include_file = std.mem.eql(u8, ext, ".c");
    //         for (disclude) |f| {
    //             if (std.mem.eql(u8, entry.basename, f)) {
    //                 include_file = false;
    //             }
    //         }
    //         for (handle_with_care) |f| {
    //             if (std.mem.eql(u8, entry.basename, f)) {
    //                 include_file = false;
    //             }
    //         }
    //         if (include_file) {
    //             // we have to clone the path as walker.next() or walker.deinit() will override/kill it
    //             const path_items = [_][] const u8{CFITS_DIR, entry.path};
    //             var full_path = try std.fs.path.join(b.allocator, &path_items);
    //             try sources.append(full_path);
    //         }
    //     }
    // }

    const sources = [_][]const u8{
        "buffers.c", "cfileio.c", "checksum.c", "drvrfile.c", "drvrmem.c", 
		"drvrnet.c", "drvrsmem.c", "editcol.c", "edithdu.c", "eval_l.c",
		"eval_y.c", "eval_f.c", "fitscore.c", "getcol.c", "getcolb.c", "getcold.c", "getcole.c",
		"getcoli.c", "getcolj.c", "getcolk.c", "getcoll.c", "getcols.c", "getcolsb.c",
		"getcoluk.c", "getcolui.c", "getcoluj.c", "getkey.c", "group.c", "grparser.c",
		"histo.c", "iraffits.c",
		"modkey.c", "putcol.c", "putcolb.c", "putcold.c", "putcole.c", "putcoli.c",
		"putcolj.c", "putcolk.c", "putcoluk.c", "putcoll.c", "putcols.c", "putcolsb.c",
		"putcolu.c", "putcolui.c", "putcoluj.c", "putkey.c", "region.c", "scalnull.c",
		"swapproc.c", "wcssub.c", "wcsutil.c", "imcompress.c", "quantize.c", "ricecomp.c",
		"pliocomp.c", "fits_hcompress.c", "fits_hdecompress.c",
		"simplerng.c",
        // zlib sources
        "zcompress.c", "zuncompress.c",
        // fitsio src
        "f77_wrap1.c", "f77_wrap2.c", "f77_wrap3.c", "f77_wrap4.c"
    };

    const cflags = [_][] const u8 {"-O2", "-Wl", "-Dg77Fortran"};
    inline for (sources) |f| {
        lib.addCSourceFile(CFITS_DIR ++ f, &cflags);
    }
    lib.linkLibC();
    lib.linkSystemLibrary("zlib");
    lib.linkSystemLibrary("libcurl");
    return lib;
}
