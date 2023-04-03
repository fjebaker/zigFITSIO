const std = @import("std");
const c = @import("c.zig");

pub const FITSError = error{
    UnknownError,
    CouldNotOpenFile,
    UnknownHDUType,
    IncompabibleDataType,
    BadColumnNumber,
    BadRowNumber,
    BadElementNumber,
};

pub fn handleErrorCode(code: usize) FITSError!void {
    return switch (code) {
        0 => return,
        104 => FITSError.CouldNotOpenFile,
        302 => FITSError.BadColumnNumber,
        307 => FITSError.BadRowNumber,
        308 => FITSError.BadElementNumber,
        else => {
            std.log.warn("CFITSIO ERROR CODE: {d}\n", .{code});
            return FITSError.UnknownError;
        },
    };
}

pub const DataType = enum {
    Byte,
    String, // char **
    Short,
    UnsignedShort,
    Int32,
    UnsignedInt32,
    Int64,
    Int128,
    UnsignedInt64,
    Float32,
    Float64,
    pub fn fromFITS(t: c_int) DataType {
        return switch (t) {
            c.TBYTE => .Byte,
            c.TSTRING => .String,
            c.TSHORT => .Short,
            c.TUSHORT => .UnsignedShort,
            c.TINT => .Int32,
            c.TUINT => .UnsignedInt32,
            c.TLONG => .Int64,
            c.TLONGLONG => .Int128,
            c.TULONG => .UnsignedInt64,
            c.TFLOAT => .Float32,
            c.TDOUBLE => .Float64,
            else => unreachable,
        };
    }
    pub fn toFITS(t: DataType) c_int {
        return switch (t) {
            .Byte => c.TBYTE,
            .String => c.TSTRING,
            .Short => c.TSHORT,
            .UnsignedShort => c.TUSHORT,
            .Int32 => c.TINT,
            .UnsignedInt32 => c.TUINT,
            .Int64 => c.TLONG,
            .Int128 => c.TLONGLONG,
            .UnsignedInt64 => c.TULONG,
            .Float32 => c.TFLOAT,
            .Float64 => c.TDOUBLE,
            else => unreachable,
        };
    }
    pub fn fromType(comptime T: type) c_int {
        return switch (T) {
            f32 => c.TFLOAT,
            f64 => c.TDOUBLE,
            u32 => c.TUINT,
            i32 => c.TINT,
            else => unreachable,
        };
    }
};

pub const HDUType = enum {
    Image,
    AsciiTable,
    BinaryTable,
    pub fn translate(i: c_int) !HDUType {
        return switch (i) {
            c.IMAGE_HDU => .Image,
            c.ASCII_TBL => .AsciiTable,
            c.BINARY_TBL => .BinaryTable,
            else => FITSError.UnknownHDUType,
        };
    }
};

pub const CARD_BYTE_LENGTH = c.FLEN_CARD;
pub const RecordInfo = [CARD_BYTE_LENGTH]u8;

pub const FITSFile = struct {
    const Self = @This();
    fp: *c.fitsfile,

    pub fn open(path: []const u8) !FITSFile {
        var status: usize = 0;
        var fp: *c.fitsfile = undefined;
        // todo: check file exists, etc. here to generate nicer errors
        _ = c.fits_open_file(
            @ptrCast([*c][*c]c.fitsfile, &fp),
            @ptrCast([*c]const u8, path),
            c.READONLY,
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);

        return .{ .fp = fp };
    }

    pub fn close(self: *Self) void {
        var status: usize = 0;
        _ = c.fits_close_file(
            self.fp,
            @ptrCast([*c]c_int, &status),
        );
    }

    pub fn readNumRecords(self: *const Self) !usize {
        var status: usize = 0;
        var nkeys: usize = 0;
        _ = c.fits_get_hdrspace(
            self.fp,
            @ptrCast([*c]c_int, &(nkeys)),
            null,
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return nkeys;
    }

    pub fn readRecord(self: *const Self, i: usize) !RecordInfo {
        var status: usize = 0;
        var card: [CARD_BYTE_LENGTH]u8 = undefined;
        _ = c.fits_read_record(
            self.fp,
            @intCast(c_int, i),
            &card,
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return card;
    }

    pub fn readNumHDUs(self: *const Self) !usize {
        var status: usize = 0;
        var count: c_int = 0;
        _ = c.fits_get_num_hdus(
            self.fp,
            @ptrCast([*c]c_int, &count),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return @intCast(usize, count);
    }

    pub fn readCurrentHDUType(self: *const Self) !HDUType {
        var status: usize = 0;
        var hdu_type: c_int = 0;
        _ = c.fits_get_hdu_type(
            self.fp,
            @ptrCast([*c]c_int, &hdu_type),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return HDUType.translate(hdu_type);
    }

    pub fn selectHDU(self: *const Self, index: usize) !HDUType {
        var status: usize = 0;
        var hdu_type: c_int = 0;
        _ = c.fits_movabs_hdu(
            self.fp,
            @intCast(c_int, index),
            @ptrCast([*c]c_int, &hdu_type),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return HDUType.translate(hdu_type);
    }

    pub fn getCurrentHDUIndex(self: *const Self) usize {
        var index: c_int = 0;
        _ = c.fits_get_hdu_num(self.fp, @ptrCast([*c]c_int, &index));
        return @intCast(usize, index);
    }

    pub fn getNumColumns(self: *const Self) !usize {
        var status: usize = 0;
        var n: c_int = 0;
        _ = c.fits_get_num_cols(
            self.fp,
            @ptrCast([*c]c_int, &n),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return @intCast(usize, n);
    }

    pub fn getNumRows(self: *const Self) !usize {
        // int fits_get_num_rows(fitsfile *fptr, long *nrows, int *status)
        // int fits_get_num_cols(fitsfile *fptr, int  *ncols, int *status)
        var status: usize = 0;
        var n: c_long = 0;
        _ = c.fits_get_num_rows(
            self.fp,
            @ptrCast([*c]c_long, &n),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
        return @intCast(usize, n);
    }

    pub const ReadColumnOptions = struct {
        first_row: usize = 1,
        first_element: usize = 1,
        null_value: ?*anyopaque = null,
    };
    pub fn readColumnInto(
        self: *const Self,
        comptime T: type,
        column_index: usize,
        column: []T,
        opt: ReadColumnOptions,
    ) !void {
        var status: usize = 0;
        const d_type: c_int = DataType.fromType(T);
        var any_null: c_int = 0;
        _ = c.fits_read_col(
            self.fp,
            d_type,
            @intCast(c_int, column_index),
            @intCast(c_int, opt.first_row),
            @intCast(c_int, opt.first_element),
            @intCast(c_int, column.len),
            opt.null_value,
            @ptrCast([*c]c_int, column.ptr),
            @ptrCast([*c]c_int, &any_null),
            @ptrCast([*c]c_int, &status),
        );
        try handleErrorCode(status);
    }
    pub fn readColumnTyped(
        self: *const Self,
        comptime T: type,
        column_index: usize,
        column_size: usize,
        alloc: std.mem.Allocator,
        opt: ReadColumnOptions,
    ) ![]T {
        var arr = try alloc.alloc(T, column_size);
        errdefer alloc.free(arr);
        try self.readColumnInto(T, column_index, arr, opt);
        return arr;
    }
};

pub const HDUInfo = struct {
    parent_file: FITSFile,
    index: usize,
    pub fn ensureChosen(self: *const HDUInfo) void {
        if (self.parent_file.getCurrentHDUIndex() != self.index) {
            _ = self.parent_file.selectHDU(self.index) catch unreachable;
        }
    }
    pub fn readHeader(self: *const HDUInfo, alloc: std.mem.Allocator) ![]RecordInfo {
        self.ensureChosen();
        // read general file info
        const n = try self.parent_file.readNumRecords();
        // allocate output
        var list = try std.ArrayList(RecordInfo).initCapacity(alloc, n);
        errdefer list.deinit();
        for (0..n) |i| {
            list.appendAssumeCapacity(try self.parent_file.readRecord(i));
        }
        return list.toOwnedSlice();
    }
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
        pub fn readColumnTyped(
            self: *const Self,
            comptime T: type,
            index: usize,
            alloc: std.mem.Allocator,
            opt: FITSFile.ReadColumnOptions,
        ) ![]T {
            const size = try self.getNumRows();
            return self.info.parent_file.readColumnTyped(T, index, size, alloc, opt);
        }
    },
    pub fn readHeader(self_union: HDU, alloc: std.mem.Allocator) ![]RecordInfo {
        return switch (self_union) {
            inline else => |self| self.info.readHeader(alloc),
        };
    }
};

fn make_hdu(parent: FITSFile, hdu_type: HDUType, index: usize) HDU {
    const info = HDUInfo{ .parent_file = parent, .index = index };
    return switch (hdu_type) {
        .Image => HDU{ .Image = .{ .info = info } },
        .AsciiTable => HDU{ .AsciiTable = .{ .info = info } },
        .BinaryTable => HDU{ .BinaryTable = .{ .info = info } },
    };
}

pub const FITS = struct {
    const Self = @This();

    fits_file: FITSFile,
    num_hdus: usize,

    pub fn initFromFile(path: []const u8) !Self {
        var fits_file = try FITSFile.open(path);
        errdefer fits_file.close();

        const num_hdus = try fits_file.readNumHDUs();

        return .{
            .fits_file = fits_file,
            .num_hdus = num_hdus,
        };
    }

    pub fn deinit(self: *Self) void {
        self.fits_file.close();
    }

    /// Return all records. Caller owns the memory.
    pub fn getAllInfo(self: *Self, alloc: std.mem.Allocator) ![]RecordInfo {
        return self.getHDU(self.fits_file.getCurrentHDUIndex()).readHeader(alloc);
    }

    pub fn getAllHDUTypes(self: *Self, alloc: std.mem.Allocator) ![]HDUType {
        var list = try std.ArrayList(HDUType).initCapacity(alloc, self.num_hdus);
        errdefer list.deinit();
        // HDU numbers start at 1
        for (1..self.num_hdus + 1) |i| {
            list.appendAssumeCapacity(try self.fits_file.selectHDU(i));
        }
        return list.toOwnedSlice();
    }

    pub fn getHDU(self: *Self, index: usize) !HDU {
        const hdu_type = try self.fits_file.selectHDU(index);
        return make_hdu(self.fits_file, hdu_type, index);
    }
};
