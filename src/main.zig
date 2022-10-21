const std = @import("std");
const c = @import("c.zig");
const fits = @import("fits.zig");

const testing = std.testing;

test "read-header" {
    const filename = "/data/astro/xmm/Mrk-335/data/1112_0306870101_SCX00000ATS.FIT";
    var f = try fits.FITSFile.open(filename);
    defer f.close();

    f.readInfo();
    var i: u32 = 1;
    while (i <= f.nkeys) : (i += 1) {
        std.debug.print(
            "{s}\n",
            .{f.readRecord(i)},
        );
    }
}
