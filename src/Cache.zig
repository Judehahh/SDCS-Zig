const std = @import("std");
const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;
const LRU = @import("LRU.zig");
const testing = std.testing;

mutex: Mutex,
allocator: Allocator,
lru: LRU,
cache_bytes: usize,

const Self = @This();

pub fn init(allocator: Allocator, cache_bytes: usize, free_mem: bool) !Self {
    return .{
        .mutex = Mutex{},
        .allocator = allocator,
        .cache_bytes = cache_bytes,
        .lru = try LRU.init(allocator, cache_bytes, free_mem),
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.lru.deinit();
}

pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    try self.lru.put(key, value);
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.lru.get(key);
}

pub fn remove(self: *Self, key: []const u8) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.lru.remove(key);
}

test "test put(), get() and remove()" {
    var cache = try Self.init(testing.allocator, 64, false);
    defer cache.deinit();

    try cache.put("key1", "value1");
    try testing.expectEqual(cache.get("key1"), "value1");

    try testing.expectEqual(cache.remove("key1"), true);
    try testing.expectEqual(cache.get("key1"), null);
}
