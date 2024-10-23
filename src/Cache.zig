const std = @import("std");
const Mutex = std.Thread.Mutex;
const Allocator = std.mem.Allocator;
const StringArrayHashMap = std.StringArrayHashMap;
const testing = std.testing;

mutex: Mutex,
allocator: Allocator,
cache: std.StringArrayHashMap([]const u8),

const Self = @This();

pub fn init(allocator: Allocator, cache_bytes: usize) !Self {
    var cache = StringArrayHashMap([]const u8).init(allocator);
    try cache.ensureTotalCapacity(cache_bytes);
    return .{
        .mutex = Mutex{},
        .allocator = allocator,
        .cache = cache,
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.cache.deinit();
}

pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    try self.cache.put(key, value);
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.cache.get(key);
}

pub fn remove(self: *Self, key: []const u8) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.cache.swapRemove(key);
}

test "test put(), get() and remove()" {
    var cache = try Self.init(testing.allocator, 64);
    defer cache.deinit();

    try cache.put("key1", "value1");
    try testing.expectEqual(cache.get("key1"), "value1");

    try testing.expectEqual(cache.remove("key1"), true);
    try testing.expectEqual(cache.get("key1"), null);
}
