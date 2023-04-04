const std = @import("std");
const c = @import("c.zig");
const datatypes = @import("datatypes.zig");

const DataType = datatypes.DataType;
const PrimativeType = datatypes.PrimativeType;
const FITSRecord = datatypes.FITSRecord;
const FITSString = datatypes.FITSString;
const CARD_BYTE_LENGTH = datatypes.CARD_BYTE_LENGTH;
const HDUType = datatypes.HDUType;

const fitserrors = @import("errors.zig");
const FITSError = fitserrors.FITSError;
const handleErrorCode = fitserrors.handleErrorCode;

const Self = @This();
fp: *c.fitsfile,

pub fn open(path: []const u8) !Self {
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

pub fn readRecord(self: *const Self, i: usize) !FITSRecord {
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
    const d_type: c_int = DataType.fromType(T).toFITS();
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
pub fn getColumnTyped(
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

pub fn readRecordInfo(self: *const Self, name: [:0]const u8) !FITSRecord {
    var status: usize = 0;
    var card: [CARD_BYTE_LENGTH]u8 = undefined;
    _ = c.fits_read_card(
        self.fp,
        name.ptr,
        &card,
        @ptrCast([*c]c_int, &status),
    );
    try handleErrorCode(status);
    return card;
}

pub fn readRecordValueTyped(
    self: *const Self,
    comptime T: type,
    name: [:0]const u8,
) !T {
    var status: usize = 0;
    var value: T = undefined;
    var comment: [CARD_BYTE_LENGTH]u8 = undefined;
    _ = c.fits_read_key(
        self.fp,
        DataType.fromType(T).toFITS(),
        name.ptr,
        @ptrCast(*anyopaque, &value),
        &comment,
        @ptrCast([*c]c_int, &status),
    );
    try handleErrorCode(status);
    return value;
}
pub fn readRecordValueString(
    self: *const Self,
    name: [:0]const u8,
) !FITSString {
    var status: usize = 0;
    var value: FITSString = undefined;
    var comment: FITSRecord = undefined;
    _ = c.fits_read_key(
        self.fp,
        PrimativeType.toFITS(.String),
        name.ptr,
        @ptrCast(*anyopaque, &value),
        &comment,
        @ptrCast([*c]c_int, &status),
    );
    try handleErrorCode(status);
    return value;
}
