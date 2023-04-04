const std = @import("std");

pub const FITSError = error{
    UnknownError,
    CouldNotOpenFile,
    UnknownHDUType,
    IncompabibleDataType,
    BadColumnNumber,
    BadRowNumber,
    BadElementNumber,
    KeyDoesNotExist,
};

pub fn handleErrorCode(code: usize) FITSError!void {
    return switch (code) {
        0 => return,
        104 => FITSError.CouldNotOpenFile,
        302 => FITSError.BadColumnNumber,
        307 => FITSError.BadRowNumber,
        308 => FITSError.BadElementNumber,
        202 => FITSError.KeyDoesNotExist,
        else => {
            std.log.warn("CFITSIO ERROR CODE: {d}\n", .{code});
            return FITSError.UnknownError;
        },
    };
}
