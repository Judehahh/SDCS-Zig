const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.log);

pub const Context = struct {
    gpa: Allocator,
    port: u16,
};

pub fn accept(context: *Context, connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var read_buffer: [8000]u8 = undefined;
    var server = std.http.Server.init(connection, &read_buffer);
    while (server.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.err("closing http connection: {s}", .{@errorName(err)});
                return;
            },
        };
        serveRequest(&request, context) catch |err| {
            log.err("unable to serve {s}: {s}", .{ request.head.target, @errorName(err) });
            return;
        };
    }
}

fn serveRequest(request: *std.http.Server.Request, context: *Context) !void {
    const method = request.head.method;

    switch (method) {
        .GET => try get(request, context),
        .POST => try post(request, context),
        .DELETE => try delete(request, context),
        else => {
            try request.respond(
                "Method not allowed",
                .{ .status = .method_not_allowed },
            );
            return;
        },
    }
}

fn get(request: *std.http.Server.Request, context: *Context) !void {
    _ = context;
    log.info("{s}: {s}", .{ @tagName(request.head.method), request.head.target });
}

fn post(request: *std.http.Server.Request, context: *Context) !void {
    _ = context;
    log.info("{s}: {s}", .{ @tagName(request.head.method), request.head.target });
}

fn delete(request: *std.http.Server.Request, context: *Context) !void {
    _ = context;
    log.info("{s}: {s}", .{ @tagName(request.head.method), request.head.target });
}
