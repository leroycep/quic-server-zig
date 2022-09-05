const std = @import("std");
const net = std.net;
const UdpSocket = @import("./udp.zig").UdpSocket;
const Packet = @import("./packet.zig").Packet;

pub fn main() !void {
    const addr = try net.Address.parseIp4("127.0.0.1", 5555);
    const sock = try UdpSocket.bind(addr);
    defer sock.deinit();
    var buf: [65536]u8 = undefined;

    // TODO(magurotuna): it may be better to use the c_allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
        const recv = try sock.recvFrom(&buf);
        std.log.info("read {} bytes from {}. received data:\n{}\n", .{
            recv.num_bytes,
            recv.src,
            std.fmt.fmtSliceHexLower(buf[0..recv.num_bytes]),
        });

        const decoded = try Packet.fromBytes(allocator, buf[0..recv.num_bytes]);
        defer decoded.deinit();

        std.log.info("received packet:\n{}\n", .{decoded});
    }
}

test {
    std.testing.refAllDecls(@This());
}
