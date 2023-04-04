const std = @import("std");

const clap = @import("clap");
const ansi = @import("ansi");
const zfits = @import("zfits");
const FITS = zfits.FITS;

const DEFAULT_HDU_INDEX = 1;

const Modes = enum {
    Default,
    Header,
    Table,
};

const Selection = struct {
    hdu_index: ?usize = null,
    row_index: ?usize = null,
    vector_index: ?usize = null,
    column_name: ?[]const u8 = null,
    max_lines: usize = 10,

    pub fn parse(s: []const u8) !Selection {
        var selection: Selection = .{};
        // split by '.'
        var itt = std.mem.tokenize(u8, s, ".");
        var depth: usize = 0;
        while (itt.next()) |token| {
            if (token[0] <= '9' and token[0] >= '0') {
                const v = try std.fmt.parseInt(usize, token, 10);
                switch (depth) {
                    0 => selection.hdu_index = v,
                    1 => selection.row_index = v,
                    2 => selection.vector_index = v,
                    else => unreachable,
                }
                depth += 1;
            } else {
                selection.column_name = token;
                if (depth < 2) {
                    // next numeric is a vector index
                    depth = 2;
                }
            }
        }
        // todo: coherency check, i.e. if vector_index is set, so must column_name
        return selection;
    }
};

test "selection-parsing" {
    var s1 = Selection.parse("4");
    std.testing.expectEqual(4, s1.hdu_index);
    var s2 = Selection.parse("4.12");
    std.testing.expectEqual(4, s2.hdu_index);
    std.testing.expectEqual(12, s2.row_index);
}

const Args = struct {
    filename: []const u8,
    mode: Modes,
    selection: Selection,
};

const Errors = error{ NoFileGiven, InvalidSelection };

fn parseArgs() !Args {
    const params = comptime clap.parseParamsComptime(
        \\--help               Display this help and exit.
        \\-h, --header         Print the header for the specified HDU.
        \\-t, --table          Print a table summary.
        \\-n, --number <usize> Maximum number of entries to display.
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

    var selection: Selection = blk: {
        if (res.positionals.len > 1) {
            var selection = try Selection.parse(res.positionals[1]);
            // set max lines if given
            if (res.args.number) |num| {
                selection.max_lines = num;
            }
            break :blk selection;
        } else {
            break :blk .{};
        }
    };

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

    const args = try parseArgs();

    var f = try FITS.initFromFile(args.filename);
    defer f.deinit();

    switch (args.mode) {
        .Default => {
            if (args.selection.hdu_index) |_| {
                try printTableSummary(&f, stdout, alloc, args.selection);
            } else {
                try printSummary(&f, stdout, alloc);
            }
        },
        .Table => {
            try printTableSummary(&f, stdout, alloc, args.selection);
        },
        .Header => {
            try printHeader(&f, stdout, alloc, args.selection);
        },
    }
    try bw.flush(); // don't forget to flush!
}

fn printHeader(f: *zfits.FITS, stdout: anytype, alloc: std.mem.Allocator, s: Selection) !void {
    var hdu = try f.getHDU(s.hdu_index orelse DEFAULT_HDU_INDEX);
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

fn printTableSummary(f: *zfits.FITS, stdout: anytype, alloc: std.mem.Allocator, selection: Selection) !void {
    var hdu = try f.getHDU(selection.hdu_index orelse DEFAULT_HDU_INDEX);
    if (hdu != .BinaryTable) {
        try std.io.getStdErr().writer().print("Selected HDU is not a table.\n", .{});
        std.os.exit(1);
    }
    const table = hdu.BinaryTable;
    const ncols = try table.getNumColumns();

    var infos = try table.getAllColumnInfo(alloc);
    defer alloc.free(infos);

    // which columns are we printing?
    var col_list = try std.ArrayList(usize).initCapacity(alloc, ncols);
    defer col_list.deinit();
    if (selection.column_name) |name| {
        // get the column index corresponding to the name
        for (infos, 1..) |info, i| {
            if (std.mem.eql(u8, info.label[0..name.len], name)) {
                // found it
                col_list.appendAssumeCapacity(i);
                break;
            }
        }
    } else {
        for (1..ncols + 1) |i| col_list.appendAssumeCapacity(i);
    }
    if (col_list.items.len == 0) {
        try std.io.getStdErr().writer().print("No valid columns selected.\n", .{});
        std.os.exit(1);
    }
    try printColumns(&hdu, stdout, alloc, selection, infos, col_list.items);
}

fn printColumns(
    hdu: *zfits.HDU,
    stdout: anytype,
    alloc: std.mem.Allocator,
    selection: Selection,
    infos: []zfits.ColumnInfo,
    columns: []usize,
) !void {
    const table = hdu.BinaryTable;
    const ncols = try table.getNumColumns();
    const nrows = try table.getNumRows();
    // print general table info
    try stdout.print("HDU#{d}: BinaryTable with dimensions ({d}x{d})\n", .{ table.info.index, ncols, nrows });

    // print column names and types
    for (columns) |i| {
        const info = infos[i - 1];
        // need to make everything constant length
        const spacing = 12 - (std.mem.indexOfScalar(u8, &info.label, 0).?);
        try stdout.print(comptime ansi.color.Bold("{s} "), .{info.label});
        for (0..spacing) |_| try stdout.print(" ", .{});
    }
    try stdout.print("\n", .{});
    for (columns) |i| {
        const info = infos[i - 1];
        // get the typename
        const tname = @tagName(info.data_type.primative());
        var spacing = 13 - (tname.len);
        try stdout.print(comptime ansi.color.Fg(.Blue, "{s}"), .{tname});
        // if vector, include the length
        if (info.data_type == .Vector) {
            spacing -= 4;
            try stdout.print("[{d}]", .{info.data_type.Vector.len});
        }
        for (0..spacing) |_| try stdout.print(" ", .{});
    }
    try stdout.print("\n------------\n", .{});

    // print the data
    if (selection.row_index) |row| {
        try printRow(hdu, stdout, alloc, infos, columns, row);
        try stdout.print("\n", .{});
    } else {
        for (1..nrows + 1) |row| {
            if (row - 1 > selection.max_lines) {
                try stdout.print(" ... +{d} rows\n", .{nrows - row});
                break;
            }
            try printRow(hdu, stdout, alloc, infos, columns, row);
            try stdout.print("\n", .{});
        }
    }
}

fn printRow(
    hdu: *zfits.HDU,
    stdout: anytype,
    alloc: std.mem.Allocator,
    infos: []zfits.ColumnInfo,
    columns: []usize,
    row: usize,
) !void {
    const table = hdu.BinaryTable;
    for (columns) |col| {
        const info = infos[col - 1];
        switch (info.data_type) {
            .Value => {
                // get the value
                const v = try table.getValueTyped(f32, col, row);
                if ((v == 0.0) or ((@fabs(v) < 10) and (@fabs(v) > 0.01))) {
                    try stdout.print("{d: <11.3}", .{v});
                } else {
                    try stdout.print("{e: <11.3}", .{v});
                }
            },
            .Vector => {
                // read the vector
                var vec = try table.getVectorTyped(f32, alloc, col, row);
                defer alloc.free(vec);
                try stdout.print("[", .{});
                for (vec, 0..) |v, i| {
                    if ((v == 0.0) or ((@fabs(v) < 10) and (@fabs(v) > 0.01))) {
                        try stdout.print("{d: <11.3}", .{v});
                    } else {
                        try stdout.print("{e: <11.3}", .{v});
                    }
                    if (columns.len != 1 and i >= 0) {
                        try stdout.print("..", .{});
                        break;
                    }
                }
                try stdout.print("]", .{});
            },
        }
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
