const std = @import("std");

const FITSFile = @import("FitsFile.zig");

const datatypes = @import("datatypes.zig");
pub const DataType = datatypes.DataType;
pub const FITSRecord = datatypes.FITSRecord;
pub const FITSString = datatypes.FITSString;
pub const HDUType = datatypes.HDUType;

const fitserrors = @import("errors.zig");
pub const FITSError = fitserrors.FITSError;
pub const handleErrorCode = fitserrors.handleErrorCode;

const hdu = @import("hdu.zig");
pub const HDU = hdu.HDU;
pub const HDUInfo = hdu.HDUInfo;
pub const ColumnInfo = hdu.ColumnInfo;
const make_hdu = hdu.make_hdu;

pub const FITS = struct {
    const Self = @This();

    fits_file: FITSFile,
    num_hdus: usize,
    path: []const u8,

    pub fn initFromFile(path: []const u8) !Self {
        var fits_file = try FITSFile.open(path);
        errdefer fits_file.close();

        const num_hdus = try fits_file.readNumHDUs();

        return .{
            .fits_file = fits_file,
            .num_hdus = num_hdus,
            .path = path,
        };
    }

    pub fn deinit(self: *Self) void {
        self.fits_file.close();
    }

    /// Return all records. Caller owns the memory.
    pub fn getAllInfo(self: *Self, alloc: std.mem.Allocator) ![]FITSRecord {
        return (try self.getHDU(self.fits_file.getCurrentHDUIndex())).readHeader(alloc);
    }

    pub fn readAllHDUs(self: *Self, alloc: std.mem.Allocator) ![]HDU {
        var list = try std.ArrayList(HDU).initCapacity(alloc, self.num_hdus);
        errdefer list.deinit();
        // HDU numbers start at 1
        for (1..self.num_hdus + 1) |i| {
            list.appendAssumeCapacity(try self.getHDU(i));
        }
        return list.toOwnedSlice();
    }

    pub fn getHDU(self: *Self, index: usize) !HDU {
        const hdu_type = try self.fits_file.selectHDU(index);
        return make_hdu(self.fits_file, hdu_type, index);
    }
};
