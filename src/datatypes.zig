const std = @import("std");
const c = @import("c.zig");

pub const CARD_BYTE_LENGTH = c.FLEN_CARD;
pub const NAME_BYTE_LENGTH = 8; // length of name in bytes
pub const FITSRecord = [CARD_BYTE_LENGTH]u8;
pub const FITSString = [NAME_BYTE_LENGTH + 1:0]u8;

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
        };
    }
    pub fn fromType(comptime T: type) DataType {
        return switch (T) {
            f32 => .Float32,
            f64 => .Float64,
            u32 => .UnsignedInt32,
            i32 => .Int32,
            else => unreachable,
        };
    }
    pub fn toType(comptime t: DataType) type {
        return switch (t) {
            .Float32 => f32,
            .Float64 => f64,
            .UnsignedInt32 => u32,
            .Int32 => i32,
            else => unreachable,
        };
    }
    pub fn fromFITSString(s: FITSString) DataType {
        for (s) |t| {
            if (t <= '9') continue;
            return switch (t) {
                'E' => .Float32,
                'D' => .Float64,
                else => continue,
            };
        }
        unreachable;
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
            else => error.UnknownHDUType,
        };
    }
};
