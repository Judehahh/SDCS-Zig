const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.Server);
const Serve = @import("Serve.zig");
const Cache = @import("Cache.zig");

const ports = [_:0]u16{ 9527, 9528, 9529 };

pub fn main() !void {
    if (std.os.argv.len != 2) {
        std.debug.print("Usage: sdcs-zig port-num", .{});
        return;
    }

    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();

    const node_num = try std.fmt.parseInt(u16, std.mem.sliceTo(std.os.argv[1], 0), 10);
    if (node_num >= ports.len) {
        std.debug.print("Only support up to {d} nodes\n", .{ports.len});
        return;
    }
    const port = ports[node_num];
    const address = try net.Address.parseIp4("127.0.0.1", port);
    var http_server = try address.listen(.{
        .reuse_address = true,
    });
    defer http_server.deinit();

    var context: Serve.Context = .{
        .allocator = gpa,
        .port = address.getPort(),
        .ports = &ports,
        .cache = try Cache.init(
            gpa,
            std.math.maxInt(u16),
            true,
        ),
    };
    defer context.cache.deinit();

    std.debug.print("Start server at http://localhost:{}\n", .{address.getPort()});

    while (true) {
        const connection = try http_server.accept();
        _ = std.Thread.spawn(.{}, Serve.accept, .{ &context, connection }) catch |err| {
            log.err("unable to accept connection: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
    }
}
