const std = @import("std");
const meta = std.meta;
const VariableLengthVector = @import("../../variable_length_vector.zig").VariableLengthVector;
const Bytes = @import("../../bytes.zig").Bytes;

const NamedGroups = VariableLengthVector(NamedGroup, 65535);

/// https://www.rfc-editor.org/rfc/rfc8446#section-4.2.7
///
/// > The "extension_data" field of this extension contains a "NamedGroupList" value:
///
/// enum {
///
///     /* Elliptic Curve Groups (ECDHE) */
///     secp256r1(0x0017), secp384r1(0x0018), secp521r1(0x0019),
///     x25519(0x001D), x448(0x001E),
///
///     /* Finite Field Groups (DHE) */
///     ffdhe2048(0x0100), ffdhe3072(0x0101), ffdhe4096(0x0102),
///     ffdhe6144(0x0103), ffdhe8192(0x0104),
///
///     /* Reserved Code Points */
///     ffdhe_private_use(0x01FC..0x01FF),
///     ecdhe_private_use(0xFE00..0xFEFF),
///     (0xFFFF)
/// } NamedGroup;
///
/// struct {
///     NamedGroup named_group_list<2..2^16-1>;
/// } NamedGroupList;
pub const NamedGroupList = struct {
    named_group_list: NamedGroups,

    const Self = @This();

    pub fn encodedLength(self: Self) usize {
        return self.named_group_list.encodedLength();
    }

    pub fn encode(self: Self, out: *Bytes) !void {
        try self.named_group_list.encode(out);
    }

    pub fn decode(allocator: std.mem.Allocator, in: *Bytes) !Self {
        return Self{
            .named_group_list = try NamedGroups.decode(allocator, in),
        };
    }

    pub fn deinit(self: Self) void {
        self.named_group_list.deinit();
    }
};

test "encode NamedGroupList" {
    const ngl = NamedGroupList{
        .named_group_list = try NamedGroups.fromSlice(std.testing.allocator, &.{ .secp256r1, .ffdhe2048 }),
    };
    defer ngl.deinit();

    var buf: [1024]u8 = undefined;
    var out = Bytes{ .buf = &buf };

    try ngl.encode(&out);

    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x04, 0x00, 0x17, 0x01, 0x00 }, out.split().former.buf);
}

test "decode NamedGroupList" {
    var buf = [_]u8{ 0x00, 0x04, 0x00, 0x17, 0x01, 0x00 };
    var in = Bytes{ .buf = &buf };

    const got = try NamedGroupList.decode(std.testing.allocator, &in);
    defer got.deinit();

    try std.testing.expectEqualSlices(NamedGroup, &.{ .secp256r1, .ffdhe2048 }, got.named_group_list.data.items);
}

/// https://www.rfc-editor.org/rfc/rfc8446#section-4.2.7
///
/// enum {
///
///     /* Elliptic Curve Groups (ECDHE) */
///     secp256r1(0x0017), secp384r1(0x0018), secp521r1(0x0019),
///     x25519(0x001D), x448(0x001E),
///
///     /* Finite Field Groups (DHE) */
///     ffdhe2048(0x0100), ffdhe3072(0x0101), ffdhe4096(0x0102),
///     ffdhe6144(0x0103), ffdhe8192(0x0104),
///
///     /* Reserved Code Points */
///     ffdhe_private_use(0x01FC..0x01FF),
///     ecdhe_private_use(0xFE00..0xFEFF),
///     (0xFFFF)
/// } NamedGroup;
pub const NamedGroup = enum(u16) {
    // Elliptic Curve Groups (ECDHE)
    secp256r1 = 0x0017,
    secp384r1 = 0x0018,
    secp521r1 = 0x0019,
    x25519 = 0x001D,
    x448 = 0x001E,

    // Finite Field Groups (DHE)
    ffdhe2048 = 0x0100,
    ffdhe3072 = 0x0101,
    ffdhe4096 = 0x0102,
    ffdhe6144 = 0x0103,
    ffdhe8192 = 0x0104,

    // Reserved Code Points
    // ffdhe_private_use(0x01FC..0x01FF),
    // ecdhe_private_use(0xFE00..0xFEFF),

    const Self = @This();
    const TagType = @typeInfo(Self).Enum.tag_type;

    pub fn encodedLength(self: Self) usize {
        _ = self;
        return @sizeOf(TagType);
    }

    pub fn encode(self: Self, out: *Bytes) !void {
        try out.put(TagType, @enumToInt(self));
    }

    pub fn decode(allocator: std.mem.Allocator, in: *Bytes) !Self {
        _ = allocator;
        const val = try in.consume(TagType);
        return meta.intToEnum(Self, val);
    }

    pub fn deinit(self: Self) void {
        // no-op
        _ = self;
    }
};

test "encode NamedGroup" {
    const x25519 = NamedGroup.x25519;
    var buf: [1024]u8 = undefined;
    var out = Bytes{ .buf = &buf };

    try x25519.encode(&out);

    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x1d }, out.split().former.buf);
}

test "decode NamedGroup" {
    var buf = [_]u8{ 0x00, 0x1d };
    var in = Bytes{ .buf = &buf };

    const got = try NamedGroup.decode(std.testing.allocator, &in);
    defer got.deinit();

    try std.testing.expectEqual(NamedGroup.x25519, got);
}
