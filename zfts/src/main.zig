const std = @import("std");

const clap = @import("clap");
const ansi = @import("ansi");
const zfits = @import("zfits");
const FITS = zfits.FITS;

const Modes = enum {
    Default,
    Header,
    Table,
};

const Selection = struct {
    hdu_index: usize,
    max_lines: ?usize = 10,

    pub fn fromText(s: []const u8) !Selection {
        const index = try std.fmt.parseInt(usize, s, 10);
        return .{ .hdu_index = index };
    }
};

const Args = struct { filename: []const u8, mode: Modes, selection: ?Selection };

const Errors = error{ NoFileGiven, InvalidSelection };

fn read_cli_args() !Args {
    const params = comptime clap.parseParamsComptime(
        \\--help               Display this help and exit.
        \\-h, --header         Print the header for the specified HDU.
        \\-t, --table          Print a table summary.
        \\-n, --number <usize> Print a table summary.
        \\<str>...             Filename and selections.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{});
        std.os.exit(0);
    }

    const filename = if (res.positionals.len > 0) res.positionals[0] else {
        try clap.usage(std.io.getStdErr().writer(), clap.Help, &params);
        std.os.exit(1);
    };

    var selection: ?Selection = if (res.positionals.len > 1)
        (try Selection.fromText(res.positionals[1]))
    else
        null;
    if (selection) |*s| {
        if (res.args.number) |n| {
            s.max_lines = n;
        } else {
            s.max_lines = 10;
        }
    }
    const mode: Modes = if (res.args.header != 0)
        .Header
    else if (res.args.table != 0)
        .Table
    else
        .Default;

    return .{ .filename = filename, .selection = selection, .mode = mode };
}

fn trim(alloc: std.mem.Allocator, s: zfits.FITSString) ![]u8 {
    const end = std.mem.indexOfScalar(u8, &s, 0).?;
    return alloc.dupe(u8, s[0..end]);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    // output stream
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try read_cli_args();

    var f = try FITS.initFromFile(args.filename);
    defer f.deinit();

    switch (args.mode) {
        .Default => {
            if (args.selection) |s| {
                try printTableSummary(&f, stdout, alloc, s);
            } else {
                try printSummary(&f, stdout, alloc);
            }
        },
        .Table => {
            if (args.selection) |s| {
                try printTableSummary(&f, stdout, alloc, s);
            } else {
                try std.io.getStdErr().writer().print("No selection made.\n", .{});
                std.os.exit(1);
            }
        },
        .Header => {
            if (args.selection) |s| {
                try printHeader(&f, stdout, alloc, s);
            } else {
                // print first header by default
                try printHeader(&f, stdout, alloc, .{ .hdu_index = 1 });
            }
        },
    }
    try bw.flush(); // don't forget to flush!
}

fn printHeader(f: *zfits.FITS, stdout: anytype, alloc: std.mem.Allocator, s: Selection) !void {
    var hdu = try f.getHDU(s.hdu_index);
    var headers = try hdu.readHeader(alloc);
    defer alloc.free(headers);
    for (headers) |header| {
        try stdout.print("{s}\n", .{header});
    }
}

fn printSummary(f: *zfits.FITS, stdout: anytype, alloc: std.mem.Allocator) !void {
    var hdus = try f.readAllHDUs(alloc);
    defer alloc.free(hdus);

    try stdout.print(comptime ansi.color.Bold("{s: <4} {s: <8} {s: <8}\n"), .{ "HDU", "Name", "Type" });
    for (hdus[1..], 2..) |hdu, i| {
        try printTableInfo(stdout, alloc, i, hdu);
        if (i > 10) {
            try stdout.print(" .\n", .{});
            try stdout.print(" .\n", .{});
            const j = hdus.len - 1;
            try printTableInfo(stdout, alloc, j, hdus[j]);
            break;
        }
    }
}

fn printTableSummary(
    f: *zfits.FITS,
    stdout: anytype,
    alloc: std.mem.Allocator,
    s: Selection,
) !void {
    var hdu = try f.getHDU(s.hdu_index);
    const max_lines = s.max_lines orelse 1000;
    switch (hdu) {
        .BinaryTable => |table| {
            const nrows = try table.getNumRows();
            const ncols = try table.getNumColumns();

            try stdout.print("BinaryTable with dimensions ({d}x{d})\n", .{ ncols, nrows });

            var columns = try table.getAllColumnInfo(alloc);
            defer alloc.free(columns);
            // get all column values
            var matrix: [][]f32 = try table.asMatrixTyped(f32, alloc);
            defer alloc.free(matrix);
            defer for (matrix) |row| {
                alloc.free(row);
            };
            for (columns) |info| {
                // need to make everything constant length
                const spacing = 10 - (std.mem.indexOfScalar(u8, &info.label, 0).?);
                try stdout.print(comptime ansi.color.Bold("{s} "), .{info.label});
                for (0..spacing) |_| try stdout.print(" ", .{});
            }
            try stdout.print("\n", .{});
            for (columns) |info| {
                const tname = @tagName(info.data_type);
                const spacing = 11 - (tname.len);
                try stdout.print(comptime ansi.color.Fg(.Blue, "{s}"), .{tname});
                for (0..spacing) |_| try stdout.print(" ", .{});
            }
            try stdout.print("\n", .{});
            for (0..nrows) |i| {
                for (0..ncols) |j| {
                    const v = matrix[j][i];
                    if ((v == 0.0) or ((@fabs(v) < 10) and (@fabs(v) > 0.01))) {
                        try stdout.print("{d: <11.3}", .{v});
                    } else {
                        try stdout.print("{e: <11.3}", .{v});
                    }
                }
                try stdout.print("\n", .{});
                if (i > max_lines) {
                    try stdout.print("...\n", .{});
                    break;
                }
            }
        },
        else => {
            try std.io.getStdErr().writer().print("Selected HDU is not a table.\n", .{});
            std.os.exit(1);
        },
    }
}

fn printTableInfo(
    stdout: anytype,
    alloc: std.mem.Allocator,
    i: usize,
    hdu: zfits.HDU,
) !void {
    var name = try hdu.readNameTrimmed(alloc);
    defer alloc.free(name);
    try stdout.print(" {d: <3} {s: <8} {s: <8}", .{ i, name, @tagName(hdu.getType()) });
    switch (hdu) {
        .BinaryTable => |table| {
            var columns = try table.getAllColumnInfo(alloc);
            defer alloc.free(columns);
            try stdout.print("[ ", .{});
            for (columns) |colinfo| {
                try stdout.print(comptime ansi.color.Fg(.Green, "{s: <8}"), .{colinfo.label[0..7]});
            }
            const ncols = try table.getNumColumns();
            const nrows = try table.getNumRows();
            try stdout.print("] ({d} x {d})", .{ ncols, nrows });
        },
        else => {},
    }
    try stdout.print("\n", .{});
}
