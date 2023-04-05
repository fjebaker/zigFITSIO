const std = @import("std");
const c = @import("c.zig");

const datatypes = @import("datatypes.zig");
const DataType = datatypes.DataType;
const FITSRecord = datatypes.FITSRecord;
const FITSString = datatypes.FITSString;
const HDUType = datatypes.HDUType;

const fitserrors = @import("errors.zig");
const FITSError = fitserrors.FITSError;
const handleErrorCode = fitserrors.handleErrorCode;

const FITSFile = @import("FitsFile.zig");

pub const HDUInfo = struct {
    parent_file: FITSFile,
    index: usize,
    pub fn ensureChosen(self: *const HDUInfo) void {
        if (self.parent_file.getCurrentHDUIndex() != self.index) {
            _ = self.parent_file.selectHDU(self.index) catch unreachable;
        }
    }
    pub fn readHeader(self: *const HDUInfo, alloc: std.mem.Allocator) ![]FITSRecord {
        self.ensureChosen();
        // read general file info
        const n = try self.parent_file.readNumRecords();
        // allocate output
        var list = try std.ArrayList(FITSRecord).initCapacity(alloc, n);
        errdefer list.deinit();
        for (0..n) |i| {
            list.appendAssumeCapacity(try self.parent_file.readRecord(i));
        }
        return list.toOwnedSlice();
    }
    pub fn readName(self: *const HDUInfo) !FITSString {
        self.ensureChosen();
        return self.parent_file.readRecordValueString("EXTNAME");
    }
};

pub const ColumnInfo = struct {
    label: FITSString,
    data_type: DataType,
    unit: ?FITSString,
};

pub const HDU = union(HDUType) {
    Image: struct {
        info: HDUInfo,
    },
    AsciiTable: struct {
        info: HDUInfo,
    },
    BinaryTable: struct {
        const Self = @This();
        info: HDUInfo,
        pub fn getNumColumns(self: *const Self) !usize {
            self.info.ensureChosen();
            return try self.info.parent_file.getNumColumns();
        }
        pub fn getNumRows(self: *const Self) !usize {
            self.info.ensureChosen();
            return try self.info.parent_file.getNumRows();
        }
        pub fn getValueTyped(
            self: *const Self,
            comptime T: type,
            column: usize,
            row: usize,
        ) !T {
            self.info.ensureChosen();
            var buf: [1]T = undefined;
            try self.info.parent_file.readColumnInto(
                T,
                column,
                &buf,
                .{ .first_row = row },
            );
            return buf[0];
        }
        pub fn getColumnTyped(
            self: *const Self,
            comptime T: type,
            index: usize,
            alloc: std.mem.Allocator,
            opt: FITSFile.ReadColumnOptions,
        ) ![]T {
            self.info.ensureChosen();
            const size = try self.getNumRows();
            return self.info.parent_file.getColumnTyped(T, index, size, alloc, opt);
        }

        pub fn getVectorTyped(
            self: *const Self,
            comptime T: type,
            alloc: std.mem.Allocator,
            col: usize,
            row: usize,
        ) ![]T {
            self.info.ensureChosen();
            const info = try self.getColumnInfo(col);
            const n_items = info.data_type.Vector.len;

            var arr = try alloc.alloc(T, n_items);
            errdefer alloc.free(arr);
            for (1..n_items + 1) |i| {
                try self.info.parent_file.readColumnInto(
                    T,
                    col,
                    arr[i - 1 .. i],
                    .{ .first_row = row, .first_element = i },
                );
            }
            return arr;
        }
        pub fn getColumnVectorTyped(
            self: *const Self,
            comptime T: type,
            index: usize,
            alloc: std.mem.Allocator,
        ) ![][]T {
            self.info.ensureChosen();

            const nrows = try self.getNumRows();
            var list = try std.ArrayList([]T).initCapacity(alloc, nrows);
            errdefer list.deinit();
            errdefer for (list.items) |item| {
                alloc.free(item);
            };
            for (1..nrows + 1) |row| {
                var vec = try self.getVectorTyped(T, alloc, index, row);
                list.appendAssumeCapacity(vec);
            }
            return list.toOwnedSlice();
        }
        pub fn getColumnInfo(self: *const Self, i: usize) !ColumnInfo {
            self.info.ensureChosen();
            // this seems un-zig-like horrendous
            // todo: find an easier way to do this
            var label_name: FITSString = .{' '} ** 8 ++ .{0};
            var format_name: FITSString = .{' '} ** 8 ++ .{0};
            var unit_name: FITSString = .{' '} ** 8 ++ .{0};
            label_name[0..5].* = "TTYPE".*;
            format_name[0..5].* = "TFORM".*;
            unit_name[0..5].* = "TUNIT".*;

            _ = std.fmt.formatIntBuf(label_name[5..], i, 10, .lower, .{ .alignment = .Left });
            _ = std.fmt.formatIntBuf(format_name[5..], i, 10, .lower, .{ .alignment = .Left });
            _ = std.fmt.formatIntBuf(unit_name[5..], i, 10, .lower, .{ .alignment = .Left });

            const label = try self.info.parent_file.readRecordValueString(&label_name);
            const format = try self.info.parent_file.readRecordValueString(&format_name);
            // units are not always given
            const unit: ?FITSString =
                self.info.parent_file.readRecordValueString(&unit_name) catch |err|
                switch (err) {
                FITSError.KeyDoesNotExist => null,
                else => return err,
            };

            return .{
                .label = label,
                .data_type = try DataType.fromFITSString(format),
                .unit = unit,
            };
        }
        pub fn getAllColumnInfo(self: *const Self, alloc: std.mem.Allocator) ![]ColumnInfo {
            self.info.ensureChosen();
            const ncols = try self.getNumColumns();
            var list = try std.ArrayList(ColumnInfo).initCapacity(alloc, ncols);
            errdefer list.deinit();
            // assemble all column infos
            for (1..ncols + 1) |i| {
                const colinfo = try self.getColumnInfo(i);
                list.appendAssumeCapacity(colinfo);
            }
            return list.toOwnedSlice();
        }
        pub fn asMatrixTyped(self: *const Self, comptime T: type, alloc: std.mem.Allocator) ![][]T {
            self.info.ensureChosen();
            const ncols = try self.getNumColumns();
            var list = try std.ArrayList([]T).initCapacity(alloc, ncols);
            errdefer list.deinit();
            errdefer for (list.items) |item| {
                alloc.free(item);
            };

            for (1..ncols + 1) |i| {
                var column = try self.getColumnTyped(T, i, alloc, .{});
                list.appendAssumeCapacity(column);
            }
            return list.toOwnedSlice();
        }
    },
    pub fn readHeader(self_union: HDU, alloc: std.mem.Allocator) ![]FITSRecord {
        return switch (self_union) {
            inline else => |self| self.info.readHeader(alloc),
        };
    }
    pub fn getType(self_union: HDU) HDUType {
        return switch (self_union) {
            .Image => .Image,
            .AsciiTable => .AsciiTable,
            .BinaryTable => .BinaryTable,
        };
    }
    pub fn readName(self_union: HDU) !FITSString {
        return switch (self_union) {
            inline else => |self| self.info.readName(),
        };
    }

    pub fn readNameTrimmed(self_union: HDU, alloc: std.mem.Allocator) ![]u8 {
        const fname = try self_union.readName();
        // find sentinel
        const i = std.mem.indexOfScalar(u8, &fname, 0).?;
        return alloc.dupe(u8, fname[0..i]);
    }
};

pub fn make_hdu(parent: FITSFile, hdu_type: HDUType, index: usize) HDU {
    const info = HDUInfo{ .parent_file = parent, .index = index };
    return switch (hdu_type) {
        .Image => HDU{ .Image = .{ .info = info } },
        .AsciiTable => HDU{ .AsciiTable = .{ .info = info } },
        .BinaryTable => HDU{ .BinaryTable = .{ .info = info } },
    };
}
