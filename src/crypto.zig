const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;
const HkdfSha256 = std.crypto.kdf.hkdf.HkdfSha256;
const VariableLengthVector = @import("./variable_length_vector.zig").VariableLengthVector;

/// Derives server_initial_secret from the given client Destination Connection ID,
/// writing the result into `out`.
/// https://www.rfc-editor.org/rfc/rfc9001#name-initial-secrets
pub fn deriveServerInitialSecret(out: *[32]u8, client_destination_connection_id: []const u8) !void {
    const initial_secret = deriveCommonInitialSecret(client_destination_connection_id);
    const label = "server in";
    const ctx = "";
    try hkdfExpandLabel(initial_secret, label, ctx, out);
}

/// Derives AEAD Key (key) from the given server_initial_secret,
/// writing the result into `out`.
pub fn deriveAradKey(out: *[16]u8, server_initial_secret: [32]u8) !void {
    const label = "quic key";
    const ctx = "";
    try hkdfExpandLabel(server_initial_secret, label, ctx, out);
}

/// Derives Initialization Vector (IV) from the given server_initial_secret,
/// writing the result into `out`.
pub fn deriveInitializationVector(out: *[12]u8, server_initial_secret: [32]u8) !void {
    const label = "quic iv";
    const ctx = "";
    try hkdfExpandLabel(server_initial_secret, label, ctx, out);
}

/// Derives Header Protection Key (hp) from the given server_initial_secret,
/// writing the result into `out`.
pub fn deriveHeaderProtectionKey(out: *[16]u8, server_initial_secret: [32]u8) !void {
    const label = "quic hp";
    const ctx = "";
    try hkdfExpandLabel(server_initial_secret, label, ctx, out);
}

const HkdfLabel = struct {
    length: u16,
    label: VariableLengthVector(u8, label_max_length),
    context: VariableLengthVector(u8, ctx_max_length),

    const Self = @This();

    const label_prefix = "tls13 ";
    const label_max_length = 255;
    const ctx_max_length = 255;

    fn encode(self: Self, out: []u8) !usize {
        var pos: usize = 0;
        mem.writeIntBig(u16, out[0..@sizeOf(u16)], self.length);
        pos += @sizeOf(u16);

        pos += try self.label.encode(out[pos..]);
        pos += try self.context.encode(out[pos..]);

        return pos;
    }
};

fn hkdfExpandLabel(secret: [32]u8, label: []const u8, ctx: []const u8, out: []u8) !void {
    if (HkdfLabel.label_prefix.len + label.len > HkdfLabel.label_max_length) {
        return error.LabelTooLong;
    }
    if (ctx.len > HkdfLabel.ctx_max_length) {
        return error.ContextTooLong;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const hkdfLabel = HkdfLabel{
        .length = @intCast(u16, out.len),
        .label = label: {
            var lbl = try ArrayList(u8).initCapacity(allocator, HkdfLabel.label_prefix.len + label.len);
            lbl.appendSliceAssumeCapacity(HkdfLabel.label_prefix);
            lbl.appendSliceAssumeCapacity(label);
            break :label .{ .data = lbl };
        },
        .context = ctx: {
            var context = try ArrayList(u8).initCapacity(allocator, ctx.len);
            context.appendSliceAssumeCapacity(ctx);
            break :ctx .{ .data = context };
        },
    };

    // TODO(magurotuna): consider more appropriate array size
    var encoded_label: [4096]u8 = undefined;
    const encoded_label_size = try hkdfLabel.encode(&encoded_label);

    HkdfSha256.expand(out, encoded_label[0..encoded_label_size], secret);
}

fn deriveCommonInitialSecret(client_destination_connection_id: []const u8) [32]u8 {
    const initial_salt = [_]u8{
        // zig fmt: off
        0x38, 0x76, 0x2c, 0xf7, 0xf5, 0x59, 0x34, 0xb3,
        0x4d, 0x17, 0x9a, 0xe6, 0xa4, 0xc8, 0x0c, 0xad,
        0xcc, 0xbb, 0x7f, 0x0a,
        // zig fmt: on
    };
    return HkdfSha256.extract(&initial_salt, client_destination_connection_id);
}

test "initial_secret" {
    {
        // This test case is brought from https://www.rfc-editor.org/rfc/rfc9001#section-a.1
        const client_dcid = [_]u8{
            // zig fmt: off
            0x83, 0x94, 0xc8, 0xf0, 0x3e, 0x51, 0x57, 0x08,
            // zig fmt: on
        };

        const got = deriveCommonInitialSecret(&client_dcid);
        const expected = [_]u8{
            // zig fmt: off
            0x7d, 0xb5, 0xdf, 0x06, 0xe7, 0xa6, 0x9e, 0x43,
            0x24, 0x96, 0xad, 0xed, 0xb0, 0x08, 0x51, 0x92,
            0x35, 0x95, 0x22, 0x15, 0x96, 0xae, 0x2a, 0xe9,
            0xfb, 0x81, 0x15, 0xc1, 0xe9, 0xed, 0x0a, 0x44,
            // zig fmt: on
        };
        try std.testing.expectEqualSlices(u8, &expected, &got);
    }

    {
        // This test case is brought from https://quic.xargs.org/
        const client_dcid = [_]u8{
            // zig fmt: off
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            // zig fmt: on
        };

        const got = deriveCommonInitialSecret(&client_dcid);
        const expected = [_]u8{
            // zig fmt: off
            0xf0, 0x16, 0xbb, 0x2d, 0xc9, 0x97, 0x6d, 0xea,
            0x27, 0x26, 0xc4, 0xe6, 0x1e, 0x73, 0x8a, 0x1e,
            0x36, 0x80, 0xa2, 0x48, 0x75, 0x91, 0xdc, 0x76,
            0xb2, 0xae, 0xe2, 0xed, 0x75, 0x98, 0x22, 0xf6,
            // zig fmt: on
        };
        try std.testing.expectEqualSlices(u8, &expected, &got);
    }
}

test "server_initial_secret" {
    {
        // This test case is brought from https://www.rfc-editor.org/rfc/rfc9001#section-a.1
        var out: [32]u8 = undefined;
        const client_dcid = [_]u8{
            // zig fmt: off
            0x83, 0x94, 0xc8, 0xf0, 0x3e, 0x51, 0x57, 0x08,
            // zig fmt: on
        };
        try deriveServerInitialSecret(&out, &client_dcid);

        const expected = [_]u8{
            // zig fmt: off
            0x3c, 0x19, 0x98, 0x28, 0xfd, 0x13, 0x9e, 0xfd,
            0x21, 0x6c, 0x15, 0x5a, 0xd8, 0x44, 0xcc, 0x81,
            0xfb, 0x82, 0xfa, 0x8d, 0x74, 0x46, 0xfa, 0x7d,
            0x78, 0xbe, 0x80, 0x3a, 0xcd, 0xda, 0x95, 0x1b
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }

    {
        // This test case is brought from https://quic.xargs.org/
        var out: [32]u8 = undefined;
        const client_dcid = [_]u8{
            // zig fmt: off
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            // zig fmt: on
        };
        try deriveServerInitialSecret(&out, &client_dcid);

        const expected = [_]u8{
            // zig fmt: off
            0xad, 0xc1, 0x99, 0x5b, 0x5c, 0xee, 0x8f, 0x03,
            0x74, 0x6b, 0xf8, 0x30, 0x9d, 0x02, 0xd5, 0xea,
            0x27, 0x15, 0x9c, 0x1e, 0xd6, 0x91, 0x54, 0x03,
            0xb3, 0x63, 0x18, 0xd5, 0xa0, 0x3a, 0xfe, 0xb8,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }
}

test "AEAD key" {
    {
        // This test case is brought from https://www.rfc-editor.org/rfc/rfc9001#section-a.1
        var out: [16]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0x3c, 0x19, 0x98, 0x28, 0xfd, 0x13, 0x9e, 0xfd,
            0x21, 0x6c, 0x15, 0x5a, 0xd8, 0x44, 0xcc, 0x81,
            0xfb, 0x82, 0xfa, 0x8d, 0x74, 0x46, 0xfa, 0x7d,
            0x78, 0xbe, 0x80, 0x3a, 0xcd, 0xda, 0x95, 0x1b
            // zig fmt: on
        };
        try deriveAradKey(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0xcf, 0x3a, 0x53, 0x31, 0x65, 0x3c, 0x36, 0x4c,
            0x88, 0xf0, 0xf3, 0x79, 0xb6, 0x06, 0x7e, 0x37,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }

    {
        // This test case is brought from https://quic.xargs.org/
        var out: [16]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0xad, 0xc1, 0x99, 0x5b, 0x5c, 0xee, 0x8f, 0x03,
            0x74, 0x6b, 0xf8, 0x30, 0x9d, 0x02, 0xd5, 0xea,
            0x27, 0x15, 0x9c, 0x1e, 0xd6, 0x91, 0x54, 0x03,
            0xb3, 0x63, 0x18, 0xd5, 0xa0, 0x3a, 0xfe, 0xb8,
            // zig fmt: on
        };
        try deriveAradKey(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0xd7, 0x7f, 0xc4, 0x05, 0x6f, 0xcf, 0xa3, 0x2b,
            0xd1, 0x30, 0x24, 0x69, 0xee, 0x6e, 0xbf, 0x90,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }
}

test "Initialization Vector (IV)" {
    {
        // This test case is brought from https://www.rfc-editor.org/rfc/rfc9001#section-a.1
        var out: [12]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0x3c, 0x19, 0x98, 0x28, 0xfd, 0x13, 0x9e, 0xfd,
            0x21, 0x6c, 0x15, 0x5a, 0xd8, 0x44, 0xcc, 0x81,
            0xfb, 0x82, 0xfa, 0x8d, 0x74, 0x46, 0xfa, 0x7d,
            0x78, 0xbe, 0x80, 0x3a, 0xcd, 0xda, 0x95, 0x1b
            // zig fmt: on
        };
        try deriveInitializationVector(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0x0a, 0xc1, 0x49, 0x3c, 0xa1, 0x90, 0x58, 0x53,
            0xb0, 0xbb, 0xa0, 0x3e,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }

    {
        // This test case is brought from https://quic.xargs.org/
        var out: [12]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0xad, 0xc1, 0x99, 0x5b, 0x5c, 0xee, 0x8f, 0x03,
            0x74, 0x6b, 0xf8, 0x30, 0x9d, 0x02, 0xd5, 0xea,
            0x27, 0x15, 0x9c, 0x1e, 0xd6, 0x91, 0x54, 0x03,
            0xb3, 0x63, 0x18, 0xd5, 0xa0, 0x3a, 0xfe, 0xb8,
            // zig fmt: on
        };
        try deriveInitializationVector(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0xfc, 0xb7, 0x48, 0xe3, 0x7f, 0xf7, 0x98, 0x60,
            0xfa, 0xa0, 0x74, 0x77,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }
}

test "header protection key" {
    {
        // This test case is brought from https://www.rfc-editor.org/rfc/rfc9001#section-a.1
        var out: [16]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0x3c, 0x19, 0x98, 0x28, 0xfd, 0x13, 0x9e, 0xfd,
            0x21, 0x6c, 0x15, 0x5a, 0xd8, 0x44, 0xcc, 0x81,
            0xfb, 0x82, 0xfa, 0x8d, 0x74, 0x46, 0xfa, 0x7d,
            0x78, 0xbe, 0x80, 0x3a, 0xcd, 0xda, 0x95, 0x1b
            // zig fmt: on
        };
        try deriveHeaderProtectionKey(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0xc2, 0x06, 0xb8, 0xd9, 0xb9, 0xf0, 0xf3, 0x76,
            0x44, 0x43, 0x0b, 0x49, 0x0e, 0xea, 0xa3, 0x14,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }

    {
        // This test case is brought from https://quic.xargs.org/
        var out: [16]u8 = undefined;
        const server_initial_secret = [_]u8{
            // zig fmt: off
            0xad, 0xc1, 0x99, 0x5b, 0x5c, 0xee, 0x8f, 0x03,
            0x74, 0x6b, 0xf8, 0x30, 0x9d, 0x02, 0xd5, 0xea,
            0x27, 0x15, 0x9c, 0x1e, 0xd6, 0x91, 0x54, 0x03,
            0xb3, 0x63, 0x18, 0xd5, 0xa0, 0x3a, 0xfe, 0xb8,
            // zig fmt: on
        };
        try deriveHeaderProtectionKey(&out, server_initial_secret);

        const expected = [_]u8{
            // zig fmt: off
            0x44, 0x0b, 0x27, 0x25, 0xe9, 0x1d, 0xc7, 0x9b,
            0x37, 0x07, 0x11, 0xef, 0x79, 0x2f, 0xaa, 0x3d,
            // zig fmt: on
        };

        try std.testing.expectEqualSlices(u8, &expected, &out);
    }
}
