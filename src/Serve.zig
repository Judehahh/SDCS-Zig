const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const json = std.json;
const fmt = std.fmt;

const log = std.log.scoped(.log);
const Cache = @import("Cache.zig");

pub const Context = struct {
    allocator: Allocator,
    port: u16,
    cache: Cache,
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
    const key = request.head.target[1..];
    log.info("{s}: {s}", .{ @tagName(request.head.method), key });
    const value = context.cache.get(key) orelse {
        try request.respond("Key not found", .{
            .status = .not_found,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/plain" },
            },
        });
        return;
    };

    try request.respond(value, .{
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}

fn post(request: *std.http.Server.Request, context: *Context) !void {
    // get request content
    const reader = try request.reader();
    const content = try reader.readAllAlloc(context.allocator, 1024);
    log.info("{s}: {s} {s}", .{ @tagName(request.head.method), request.head.target, content });

    // add to cache
    var parsed = try json.parseFromSlice(json.Value, context.allocator, content, .{});
    defer parsed.deinit();

    const key = try context.allocator.dupe(u8, parsed.value.object.keys()[0]);
    try context.cache.put(key, content);

    // respond
    try request.respond("", .{
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}

fn delete(request: *std.http.Server.Request, context: *Context) !void {
    const key = request.head.target[1..];
    log.info("{s}: {s}", .{ @tagName(request.head.method), key });

    const num = if (context.cache.remove(key)) @as(u8, 1) else @as(u8, 0);
    const content = try fmt.allocPrint(context.allocator, "{d}", .{num});

    try request.respond(content, .{
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}
