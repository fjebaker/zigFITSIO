const std = @import("std");
const c = @import("c.zig");
const fits = @import("fits.zig");

const FITS = fits.FITS;

const testing = std.testing;

test "read-header" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    const filename = "/Users/lx21966/Developer/relline/rel_table.fits";
    var f = try FITS.initFromFile(filename);
    defer f.deinit();

    std.debug.print("Num HDUs: {d}\n", .{f.num_hdus});
    // var hdutypes = try f.getAllHDUTypes(alloc);
    // defer alloc.free(hdutypes);

    // for (hdutypes) |t| {
    //     std.debug.print("{}\n", .{t});
    // }

    const hdu = try f.getHDU(2);
    var headers = try hdu.readHeader(alloc);
    defer alloc.free(headers);

    for (headers) |h| {
        std.debug.print("{s}\n", .{h});
    }

    const cols = try hdu.BinaryTable.getNumColumns();
    const rows = try hdu.BinaryTable.getNumRows();

    std.debug.print("Dimensions {d} x {d}\n", .{ rows, cols });

    var data = try hdu.BinaryTable.readColumnTyped(f32, 1, alloc, .{});
    defer alloc.free(data);

    std.debug.print("{any}\n", .{data});

    std.debug.print("\n", .{});

    // var infos = try f.getAllInfo(alloc);
    // defer alloc.free(infos);

    // for (infos) |info| {
    //     std.debug.print("{s}\n", .{info});
    // }

    // try f.readInfo();
    // var i: u32 = 1;
    // while (i <= f.nkeys) : (i += 1) {
    //     std.debug.print(
    //         "{s}\n",
    //         .{f.readRecord(i)},
    //     );
    // }
}
