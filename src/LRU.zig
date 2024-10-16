const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const StringArrayHashMap = std.StringArrayHashMap;
const testing = std.testing;

max_bytes: usize,
nbytes: usize,
allocator: Allocator,
map: StringArrayHashMap(*Node),
list: DoublyLinkedList(Entry),
free_mem: bool,

const log = std.log.scoped(.LRU);
const Self = @This();

pub fn init(allocator: Allocator, max_bytes: usize, free_mem: bool) !Self {
    var self = Self{
        .max_bytes = max_bytes,
        .nbytes = 0,
        .allocator = allocator,
        .map = StringArrayHashMap(*Node).init(allocator),
        .list = DoublyLinkedList(Entry){},
        .free_mem = free_mem,
    };
    try self.map.ensureTotalCapacity(self.max_bytes);
    return self;
}

pub fn deinit(self: *Self) void {
    for (self.map.keys()) |k| {
        _ = self.remove(k);
    }
    std.debug.assert(self.nbytes == 0);
    self.map.deinit();
}

pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
    if (self.map.get(key)) |node| {
        self.list.remove(node);
        self.list.prepend(node);
        self.nbytes += value.len - node.data.value.len;
        if (self.free_mem) {
            self.allocator.free(node.data.value);
        }
        node.data.value = value;
    } else {
        const node = try self.allocator.create(Node);
        node.* = .{ .data = Entry{ .key = key, .value = value } };
        try self.map.put(key, node);
        self.list.prepend(node);
        self.nbytes += key.len + value.len;
    }

    if (self.nbytes > self.max_bytes) {
        log.err("max_bytes of LRU reached, please add more memory", .{});
        return error.OutOfMemory;
    }
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    const node = self.map.get(key) orelse return null;
    self.list.remove(node);
    self.list.prepend(node);
    return node.data.value;
}

pub fn remove(self: *Self, key: []const u8) bool {
    if (self.map.get(key)) |node| {
        self.list.remove(node);
        _ = self.map.swapRemove(node.data.key);
        self.nbytes -= node.data.key.len + node.data.value.len;
        if (self.free_mem) {
            self.allocator.free(node.data.key);
            self.allocator.free(node.data.value);
        }
        self.allocator.destroy(node);
        return true;
    }
    return false;
}

pub fn len(self: *Self) usize {
    return self.list.len;
}

const Entry = struct {
    key: []const u8,
    value: []const u8,
};

const Node = DoublyLinkedList(Entry).Node;

test "test put(), get() and remove()" {
    var lru = try Self.init(testing.allocator, 1000, false);
    defer lru.deinit();

    // test get
    try lru.put("key1", "1234");
    try lru.put("key2", "abcd");

    // test get
    var result = lru.get("key1");
    try std.testing.expectEqual(result, "1234");

    result = lru.get("key2");
    try std.testing.expectEqual(result, "abcd");

    // test delete
    try std.testing.expectEqual(lru.remove("key1"), true);
    try std.testing.expectEqual(lru.remove("key1"), false);

    // test get after delete
    try std.testing.expectEqual(lru.get("key1"), null);
    try std.testing.expectEqual(lru.get("key2"), "abcd");
}
