const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.Server);
const Serve = @import("Serve.zig");
const Cache = @import("Cache.zig");

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();

    const address = try net.Address.parseIp4("127.0.0.1", 10086);
    var http_server = try address.listen(.{
        .reuse_address = true,
    });
    defer http_server.deinit();

    var context: Serve.Context = .{
        .allocator = gpa,
        .port = address.getPort(),
        .cache = try Cache.init(
            gpa,
            std.math.maxInt(u16),
            true,
        ),
    };
    defer context.cache.deinit();

    log.info("Start server at http://localhost:{}", .{address.getPort()});

    while (true) {
        const connection = try http_server.accept();
        _ = std.Thread.spawn(.{}, Serve.accept, .{ &context, connection }) catch |err| {
            log.err("unable to accept connection: {s}", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
    }
}
