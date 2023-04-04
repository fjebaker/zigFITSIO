const std = @import("std");
const c = @import("c.zig");

pub const CARD_BYTE_LENGTH = c.FLEN_CARD;
pub const NAME_BYTE_LENGTH = 8; // length of name in bytes
pub const FITSRecord = [CARD_BYTE_LENGTH]u8;
pub const FITSString = [NAME_BYTE_LENGTH + 1:0]u8;

pub const PrimativeType = enum {
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
    pub fn toFITS(t: PrimativeType) c_int {
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
};

pub const DataType = union(enum) {
    Value: PrimativeType,
    Vector: struct { subtype: PrimativeType, len: usize },
    pub fn fromFITS(t: c_int) DataType {
        return switch (t) {
            c.TBYTE => DataType.Value{.Byte},
            c.TSTRING => DataType.Value{.String},
            c.TSHORT => DataType.Value{.Short},
            c.TUSHORT => DataType.Value{.UnsignedShort},
            c.TINT => .{ .Value = .Int32 },
            c.TUINT => .{ .Value = .UnsignedInt32 },
            c.TLONG => .{ .Value = .Int64 },
            c.TLONGLONG => .{ .Value = .Int128 },
            c.TULONG => .{ .Value = .UnsignedInt64 },
            c.TFLOAT => .{ .Value = .Float32 },
            c.TDOUBLE => .{ .Value = .Float64 },
            else => unreachable,
        };
    }
    pub fn toFITS(t: DataType) c_int {
        return t.primative().toFITS();
    }
    pub fn fromType(comptime T: type) DataType {
        return switch (T) {
            f32 => .{ .Value = .Float32 },
            f64 => .{ .Value = .Float64 },
            u32 => .{ .Value = .UnsignedInt32 },
            i32 => .{ .Value = .Int32 },
            else => unreachable,
        };
    }
    pub fn primative(t: DataType) PrimativeType {
        return switch (t) {
            .Value => |v| v,
            .Vector => |v| v.subtype,
        };
    }

    pub fn toType(comptime t: DataType) type {
        return switch (t.primative()) {
            .Float32 => f32,
            .Float64 => f64,
            .UnsignedInt32 => u32,
            .Int32 => i32,
            else => unreachable,
        };
    }
    pub fn fromFITSString(s: FITSString) !DataType {
        var size: usize = 0;
        var dt: PrimativeType = undefined;
        for (s, 0..) |t, i| {
            if (t <= '9') {
                continue;
            }
            dt = switch (t) {
                'E' => .Float32,
                'D' => .Float64,
                // todo: haven't handled these yet
                else => unreachable,
            };
            // read in the size
            size = try std.fmt.parseInt(usize, s[0..i], 10);
            break;
        }
        if (size > 1) {
            return .{ .Vector = .{ .subtype = dt, .len = size } };
        }
        return .{ .Value = dt };
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
