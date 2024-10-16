const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const json = std.json;
const fmt = std.fmt;

const log = std.log.scoped(.Server);
const Cache = @import("Cache.zig");

pub const Context = struct {
    allocator: Allocator,
    port: u16,
    ports: [:0]const u16,
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
    const is_rpc = std.mem.startsWith(u8, request.head.target, "/_rpc");
    const key = if (is_rpc) request.head.target[6..] else request.head.target[1..];
    log.info("{s}: {s}", .{ @tagName(request.head.method), key });

    // get from local
    if (context.cache.get(key)) |value| {
        try request.respond(value, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/plain" },
            },
        });
        return;
    }

    // get from other nodes
    if (!is_rpc) {
        for (context.ports) |p| {
            if (p == context.port) {
                continue;
            }

            var client = http.Client{ .allocator = context.allocator };
            defer client.deinit();

            const url = try std.fmt.allocPrint(context.allocator, "http://127.0.0.1:{d}/_rpc/{s}", .{ p, key });
            defer context.allocator.free(url);

            var body = std.ArrayList(u8).init(context.allocator);
            defer body.deinit();

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .response_storage = .{ .dynamic = &body },
            });

            if (result.status == .ok) {
                // cache the value in local
                const key_dupe = try context.allocator.dupe(u8, key);
                const value_dupe = try context.allocator.dupe(u8, body.items);
                try context.cache.put(key_dupe, value_dupe);
                try request.respond(value_dupe, .{
                    .keep_alive = false,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = "text/plain" },
                    },
                });
                return;
            }
        }
    }

    // key not found in all nodes
    try request.respond("Key not found", .{
        .status = .not_found,
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}

fn post(request: *std.http.Server.Request, context: *Context) !void {
    const is_rpc = std.mem.startsWith(u8, request.head.target, "/_rpc");

    // get request content
    const reader = try request.reader();
    const content = try reader.readAllAlloc(context.allocator, 1024);
    log.info("{s}: {s} {s}", .{ @tagName(request.head.method), request.head.target, content });

    // add to cache
    var parsed = try json.parseFromSlice(json.Value, context.allocator, content, .{});
    defer parsed.deinit();

    const key = try context.allocator.dupe(u8, parsed.value.object.keys()[0]);
    try context.cache.put(key, content);

    // update to other nodes
    if (!is_rpc) {
        for (context.ports) |p| {
            if (p == context.port) {
                continue;
            }

            var client = http.Client{ .allocator = context.allocator };
            defer client.deinit();

            const url = try std.fmt.allocPrint(context.allocator, "http://127.0.0.1:{d}/_rpc/{s}", .{ p, key });
            defer context.allocator.free(url);

            var body = std.ArrayList(u8).init(context.allocator);
            defer body.deinit();

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .response_storage = .{ .dynamic = &body },
            });

            if (result.status == .ok) {
                const content_remote = body.items;

                if (std.mem.eql(u8, content, content_remote))
                    continue;

                log.info("update value to remote node {d}", .{p});

                const uri = try std.Uri.parse(url);
                var buf: [1024]u8 = undefined;
                var request_rpc = try client.open(.POST, uri, .{
                    .server_header_buffer = &buf,
                });
                defer request_rpc.deinit();
                request_rpc.transfer_encoding = .chunked;
                try request_rpc.send();
                try request_rpc.writeAll(content);
                try request_rpc.finish();
                try request_rpc.wait();
            }
        }
    }

    // respond
    try request.respond("", .{
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}

fn delete(request: *std.http.Server.Request, context: *Context) !void {
    const is_rpc = std.mem.startsWith(u8, request.head.target, "/_rpc");
    const key = if (is_rpc) request.head.target[6..] else request.head.target[1..];
    log.info("{s}: {s}", .{ @tagName(request.head.method), key });

    var delete_flag = context.cache.remove(key);

    // delete cache in other node
    if (!is_rpc) {
        for (context.ports) |p| {
            if (p == context.port) {
                continue;
            }

            var client = http.Client{ .allocator = context.allocator };
            defer client.deinit();

            const url = try std.fmt.allocPrint(context.allocator, "http://127.0.0.1:{d}/_rpc/{s}", .{ p, key });
            defer context.allocator.free(url);

            var buf: [1024]u8 = undefined;
            const uri = try std.Uri.parse(url);

            var request_rpc = try client.open(.DELETE, uri, .{
                .server_header_buffer = &buf,
            });
            defer request_rpc.deinit();

            try request_rpc.send();
            try request_rpc.finish();
            try request_rpc.wait();

            if (request_rpc.response.status == .ok) {
                const body = try request_rpc.reader().readAllAlloc(context.allocator, 256);
                defer context.allocator.free(body);
                if (body[0] != '0')
                    delete_flag = true;
            }
        }
    }

    const content = try fmt.allocPrint(context.allocator, "{d}", .{@intFromBool(delete_flag)});

    try request.respond(content, .{
        .keep_alive = false,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "text/plain" },
        },
    });
}
