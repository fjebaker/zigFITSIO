const std = @import("std");
const c = @import("c.zig");

pub const FITSError = error{FITSUnknownError};

pub fn handleErrorCode(code: usize) !void {
    switch (code) {
        0 => {
            // all good
        },
        else => {
            return FITSError.FITSUnknownError;
        },
    }
}

const CARD_BYTE_LENGTH = c.FLEN_CARD;

pub const FITSFile = struct {
    const Self = @This();

    fp: *c.fitsfile,
    nkeys: usize = 0,

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

    pub fn readInfo(self: *Self) void {
        var status: usize = 0;
        _ = c.fits_get_hdrspace(
            self.fp,
            @ptrCast([*c]c_int, &(self.nkeys)),
            null,
            @ptrCast([*c]c_int, &status),
        );
    }

    pub fn readRecord(self: *Self, i: usize) [CARD_BYTE_LENGTH]u8 {
        var status: usize = 0;
        var card: [CARD_BYTE_LENGTH]u8 = undefined;
        _ = c.fits_read_record(
            self.fp,
            @intCast(c_int, i),
            &card,
            @ptrCast([*c]c_int, &status),
        );
        return card;
    }
};
