const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const crypto = @import("./crypto.zig");
const tls = @import("./tls.zig");
const packet = @import("./packet.zig");

/// https://www.rfc-editor.org/rfc/rfc9000.html#name-packet-numbers
///
/// > Packet numbers are divided into three spaces in QUIC:
/// > Initial space:          All Initial packets (Section 17.2.2) are in this space.
/// > Handshake space:        All Handshake packets (Section 17.2.4) are in this space.
/// > Application data space: All 0-RTT (Section 17.2.3) and 1-RTT (Section 17.3.1) packets are in this space.
pub const PacketNumberSpaces = struct {
    initial: PacketNumberSpace,
    handshake: PacketNumberSpace,
    application_data: PacketNumberSpace,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .initial = PacketNumberSpace.init(allocator),
            .handshake = PacketNumberSpace.init(allocator),
            .application_data = PacketNumberSpace.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.initial.deinit();
        self.handshake.deinit();
        self.application_data.deinit();
    }

    /// Get the packet number space corresponding to the given packet type.
    pub fn getByPacketType(
        self: Self,
        packet_type: packet.PacketType,
    ) error{NoCorrespondingPacketNameSpace}!PacketNumberSpace {
        return switch (packet_type) {
            .initial => self.initial,
            .handshake => self.handshake,
            .zero_rtt, .one_rtt => self.application_data,
            .retry, .version_negotiation => error.NoCorrespondingPacketNameSpace,
        };
    }

    pub fn setInitialCryptor(self: *Self, allocator: Allocator, client_dcid: []const u8, is_server: bool) !void {
        const keys = try tls.Keys.initial(allocator, client_dcid, is_server);
        self.initial.encryptor = keys.local;
        self.initial.decryptor = keys.remote;
    }
};

/// Manage the acknowledged ranges.
/// https://www.rfc-editor.org/rfc/rfc9000.html#ack-ranges
pub const RangeSet = struct {
    // TODO(magurotuna)
};

/// Represent the QUIC's stream.
/// https://www.rfc-editor.org/rfc/rfc9000.html#name-streams
pub const Stream = struct {
    // TODO(magurotuna)
};

/// https://www.rfc-editor.org/rfc/rfc9000.html#name-packet-numbers
///
/// > Packet numbers are divided into three spaces in QUIC:
/// > Initial space:          All Initial packets (Section 17.2.2) are in this space.
/// > Handshake space:        All Handshake packets (Section 17.2.4) are in this space.
/// > Application data space: All 0-RTT (Section 17.2.3) and 1-RTT (Section 17.3.1) packets are in this space.
///
/// > As described in [QUIC-TLS], each packet type uses different protection keys.
///
/// > Conceptually, a packet number space is the context in which a packet can be processed and acknowledged.
/// > Initial packets can only be sent with Initial packet protection keys and acknowledged in packets that
/// > are also Initial packets. Similarly, Handshake packets are sent at the Handshake encryption level and
/// > can only be acknowledged in Handshake packets.
pub const PacketNumberSpace = struct {
    largest_recv_packet_number: u64 = 0,
    largest_recv_packet_time: u64 = 0,
    largest_recv_non_probing_packet_number: u64 = 0,

    /// https://www.rfc-editor.org/rfc/rfc9000.html#name-packet-numbers
    ///
    /// > Packet numbers in each space start at packet number 0. Subsequent packets sent in
    /// > the same packet number space MUST increase the packet number by at least one.
    next_packet_number: u64 = 0,

    recv_packet_need_ack: RangeSet = .{},

    /// https://www.rfc-editor.org/rfc/rfc9000.html#name-packet-numbers
    ///
    /// > Endpoints that track all individual packets for the purposes of detecting duplicates are
    /// > at risk of accumulating excessive state. The data required for detecting duplicates can be
    /// > limited by maintaining a minimum packet number below which all packets are immediately dropped.
    ///
    /// This field is used to detect duplicate packets. We use HashSet to store the already-received
    /// packet numbers, but it can use too much memory. We should reduce the memory usage by adopting
    /// the technique introduced in the RFC.
    recv_packet_number: AutoHashMap(u64, void),

    ack_elicited: bool = false,

    encryptor: ?tls.Cryptor = null,
    decryptor: ?tls.Cryptor = null,

    zero_rtt_encryptor: ?tls.Cryptor = null,
    zero_rtt_decryptor: ?tls.Cryptor = null,

    /// https://www.rfc-editor.org/rfc/rfc9000.html#name-crypto-frames
    ///
    /// > CRYPTO frames are functionally identical to STREAM frames, except that they do not
    /// > bear a stream identifier; they are not flow controlled; and they do not carry markers
    /// > for optional offset, optional length, and the end of the stream.
    ///
    /// > Unlike STREAM frames, which include a stream ID indicating to which stream the data
    /// > belongs, the CRYPTO frame carries data for a single stream **per encryption level**.
    /// > The stream does not have an explicit end, so CRYPTO frames do not have a FIN bit.
    crypto_stream: Stream = .{},

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .recv_packet_number = AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.recv_packet_number.deinit();
        if (self.encryptor) |*x| x.deinit();
        if (self.decryptor) |*x| x.deinit();
        if (self.zero_rtt_encryptor) |*x| x.deinit();
        if (self.zero_rtt_decryptor) |*x| x.deinit();
    }
};