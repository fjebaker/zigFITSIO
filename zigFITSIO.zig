const std = @import("std");
const zigFITSIO = @import("./build.zig");

const ROOT = zigFITSIO.ROOT;
const CFITS_DIR = zigFITSIO.CFITS_DIR;

pub const Library = struct {
    cfitsio: *std.build.CompileStep,
    zfitsio: *std.build.Module,
    pub fn link(self: @This(), other: *std.build.CompileStep) void {
        other.addIncludePath(CFITS_DIR);
        other.linkLibrary(self.cfitsio);
        other.addModule("zigfitsio", self.zfitsio);
    }
};

pub fn create(b: *std.Build, target: std.zig.CrossTarget) Library {
    const libcfitsio = zigFITSIO.createCFITSIO(b, target);
    const zfitsio = b.addModule("zfitsio", .{
        .source_file = .{ .path = ROOT ++ "./src/main.zig" },
        .dependencies = &.{},
    });

    return .{ .cfitsio = libcfitsio, .zfitsio = zfitsio };
}
