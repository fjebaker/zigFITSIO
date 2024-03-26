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
        @as([*c][*c]c.fitsfile, @ptrCast(&fp)),
        @as([*c]const u8, @ptrCast(path)),
        c.READONLY,
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);

    return .{ .fp = fp };
}

pub fn close(self: *Self) void {
    var status: usize = 0;
    _ = c.fits_close_file(
        self.fp,
        @as([*c]c_int, @ptrCast(&status)),
    );
}

pub fn readNumRecords(self: *const Self) !usize {
    var status: usize = 0;
    var nkeys: usize = 0;
    _ = c.fits_get_hdrspace(
        self.fp,
        @as([*c]c_int, @ptrCast(&(nkeys))),
        null,
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return nkeys;
}

pub fn readRecord(self: *const Self, i: usize) !FITSRecord {
    var status: usize = 0;
    var card: [CARD_BYTE_LENGTH]u8 = undefined;
    _ = c.fits_read_record(
        self.fp,
        @as(c_int, @intCast(i)),
        &card,
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return card;
}

pub fn readNumHDUs(self: *const Self) !usize {
    var status: usize = 0;
    var count: c_int = 0;
    _ = c.fits_get_num_hdus(
        self.fp,
        @as([*c]c_int, @ptrCast(&count)),
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return @as(usize, @intCast(count));
}

pub fn readCurrentHDUType(self: *const Self) !HDUType {
    var status: usize = 0;
    var hdu_type: c_int = 0;
    _ = c.fits_get_hdu_type(
        self.fp,
        @as([*c]c_int, @ptrCast(&hdu_type)),
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return HDUType.translate(hdu_type);
}

pub fn selectHDU(self: *const Self, index: usize) !HDUType {
    var status: usize = 0;
    var hdu_type: c_int = 0;
    _ = c.fits_movabs_hdu(
        self.fp,
        @as(c_int, @intCast(index)),
        @as([*c]c_int, @ptrCast(&hdu_type)),
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return HDUType.translate(hdu_type);
}

pub fn getCurrentHDUIndex(self: *const Self) usize {
    var index: c_int = 0;
    _ = c.fits_get_hdu_num(self.fp, @as([*c]c_int, @ptrCast(&index)));
    return @as(usize, @intCast(index));
}

pub fn getNumColumns(self: *const Self) !usize {
    var status: usize = 0;
    var n: c_int = 0;
    _ = c.fits_get_num_cols(
        self.fp,
        @as([*c]c_int, @ptrCast(&n)),
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return @as(usize, @intCast(n));
}

pub fn getNumRows(self: *const Self) !usize {
    // int fits_get_num_rows(fitsfile *fptr, long *nrows, int *status)
    // int fits_get_num_cols(fitsfile *fptr, int  *ncols, int *status)
    var status: usize = 0;
    var n: c_long = 0;
    _ = c.fits_get_num_rows(
        self.fp,
        @as([*c]c_long, @ptrCast(&n)),
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return @as(usize, @intCast(n));
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
        @as(c_int, @intCast(column_index)),
        @as(c_int, @intCast(opt.first_row)),
        @as(c_int, @intCast(opt.first_element)),
        @as(c_int, @intCast(column.len)),
        opt.null_value,
        @as([*c]c_int, @ptrCast(column.ptr)),
        @as([*c]c_int, @ptrCast(&any_null)),
        @as([*c]c_int, @ptrCast(&status)),
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
    const arr = try alloc.alloc(T, column_size);
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
        @as([*c]c_int, @ptrCast(&status)),
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
        @as(*anyopaque, @ptrCast(&value)),
        &comment,
        @as([*c]c_int, @ptrCast(&status)),
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
        @as(*anyopaque, @ptrCast(&value)),
        &comment,
        @as([*c]c_int, @ptrCast(&status)),
    );
    try handleErrorCode(status);
    return value;
}
