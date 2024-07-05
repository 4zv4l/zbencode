const std = @import("std");
const Allocator = std.mem.Allocator;
pub const List = std.ArrayList(Token);
pub const Map = std.StringArrayHashMapUnmanaged(Token);
const Bencoder = @This();

// final struct given to user
pub const Bencode = struct {
    arena: std.heap.ArenaAllocator,
    root: Token,

    pub fn init(allocator: Allocator) Bencode {
        return Bencode{ .arena = std.heap.ArenaAllocator.init(allocator), .root = undefined };
    }

    pub fn deinit(self: *Bencode) void {
        self.arena.deinit();
    }

    pub fn format(self: Bencode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt; // autofix
        _ = options; // autofix
        try writer.print("{}", .{self.root});
    }
};

// used to parse token
const Reader = struct { stream: std.io.FixedBufferStream([]const u8), ally: Allocator };

pub const Token = union(enum) {
    integer: i64,
    string: []const u8,
    list: List,
    dictionnary: Map,

    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .integer => |i| {
                try writer.print("{d}", .{i});
            },
            .string => |s| {
                try writer.print("\"{s}\"", .{s});
            },
            .list => |l| {
                var sep: []const u8 = " ";
                try writer.print("[", .{});
                for (l.items) |item| {
                    try writer.print("{s}{}", .{ sep, item });
                    sep = ", ";
                }
                try writer.print(" ]", .{});
            },
            .dictionnary => |d| {
                var sep: []const u8 = " ";
                try writer.print("{{", .{});
                for (d.keys(), d.values()) |k, v| {
                    try writer.print("{s}\"{s}\": {}", .{ sep, k, v });
                    sep = ", ";
                }
                try writer.print(" }}", .{});
            },
        }
    }

    pub fn encode(self: Token, writer: anytype) !void {
        switch (self) {
            .integer => |i| {
                try writer.print("i{d}e", .{i});
            },
            .string => |s| {
                try writer.print("{d}:{s}", .{ s.len, s });
            },
            .list => |l| {
                try writer.print("l", .{});
                for (l.items) |item| try item.encode(writer);
                try writer.print("e", .{});
            },
            .dictionnary => |d| {
                try writer.print("d", .{});
                for (d.keys(), d.values()) |k, v| {
                    try writer.print("{d}:{s}", .{ k.len, k });
                    try v.encode(writer);
                }
                try writer.print("e", .{});
            },
        }
    }
};

// i32e
// i-32e
fn parseInteger(r: *Reader) !Token {
    var buff: [1024]u8 = undefined;
    if (try r.stream.reader().readByte() != 'i') return error.ExpectedIntegerStart; // skip i
    const num = r.stream.reader().readUntilDelimiter(&buff, 'e') catch return error.BadNumber;
    return Token{ .integer = try std.fmt.parseInt(i64, num, 10) };
}

// 3:foo
fn parseString(r: *Reader) !Token {
    var buff: [1024]u8 = undefined;
    const num = try r.stream.reader().readUntilDelimiter(&buff, ':');
    const len = try std.fmt.parseUnsigned(usize, num, 10);

    const string = try r.ally.alloc(u8, len);
    errdefer r.ally.free(string);
    _ = try r.stream.read(string);
    return Token{ .string = string };
}

// li34e3:Fooe
fn parseList(r: *Reader) !Token {
    var list = List.init(r.ally);
    errdefer list.deinit();

    if (try r.stream.reader().readByte() != 'l') return error.ExpectedListStart; // skip l

    while (try r.stream.reader().readByte() != 'e') {
        try r.stream.seekTo(r.stream.pos - 1);
        try list.append(try parseAny(r));
    }

    return Token{ .list = list };
}

// d3:Foo133ee
fn parseDictionnary(r: *Reader) !Token {
    var map = Map{};
    if (try r.stream.reader().readByte() != 'd') return error.ExpectedDictionnaryStart; // skip d

    while (try r.stream.reader().readByte() != 'e') {
        try r.stream.seekTo(r.stream.pos - 1);
        const k = try parseString(r);
        const v = try parseAny(r);
        try map.put(r.ally, k.string, v);
    }
    return Token{ .dictionnary = map };
}

fn parseAny(r: *Reader) anyerror!Token {
    const c = try r.stream.reader().readByte();
    try r.stream.seekTo(r.stream.pos - 1);

    return switch (c) {
        'i' => try parseInteger(r),
        '-', '0'...'9' => try parseString(r),
        'l' => try parseList(r),
        'd' => try parseDictionnary(r),
        else => return error.InvalidDelimiter,
    };
}

pub fn parse(allocator: Allocator, data: []const u8) !Bencode {
    var bencode = Bencode.init(allocator);
    errdefer bencode.deinit();

    const stream = std.io.fixedBufferStream(data);
    var reader = Reader{ .ally = bencode.arena.allocator(), .stream = stream };

    bencode.root = try parseAny(&reader);
    return bencode;
}

///// TEST

test parseInteger {
    const testing = std.testing;
    const data = "i34e";
    var reader = Reader{ .stream = std.io.fixedBufferStream(data), .ally = testing.allocator };
    const tk = try parseInteger(&reader);
    try testing.expect(tk == .integer);
    try testing.expectEqual(tk.integer, 34);
}

test parseString {
    const testing = std.testing;
    const data = "3:Foo";
    var reader = Reader{ .stream = std.io.fixedBufferStream(data), .ally = testing.allocator };
    const tk = try parseString(&reader);
    defer testing.allocator.free(tk.string);
    try testing.expect(tk == .string);
    try testing.expectEqualStrings(tk.string, "Foo");
}

test parseList {
    const testing = std.testing;
    const data = "li34e3:Fooe";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var reader = Reader{ .stream = std.io.fixedBufferStream(data), .ally = arena.allocator() };
    const tk = try parseList(&reader);
    defer arena.deinit();
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parseDictionnary {
    const testing = std.testing;
    const data = "d3:Foo3:Bar3:Bari33ee";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var reader = Reader{ .stream = std.io.fixedBufferStream(data), .ally = arena.allocator() };
    const tk = try parseDictionnary(&reader);
    defer arena.deinit();
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parseAny {
    const testing = std.testing;
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ei35eee";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    var reader = Reader{ .stream = std.io.fixedBufferStream(data), .ally = arena.allocator() };
    const tk = try parseAny(&reader);
    defer arena.deinit();
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parse {
    const testing = std.testing;
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ed5:Hello5:Worldeee";
    var bencode = try parse(testing.allocator, data);
    defer bencode.deinit();
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{bencode.root});
}

test "encode" {
    const testing = std.testing;

    // create data structure
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ed5:Hello5:Worldeee";
    var bencode = try parse(testing.allocator, data);
    defer bencode.deinit();
    std.debug.print("\n", .{});
    std.debug.print("{}\n\n", .{bencode.root});

    // encode it
    var buff: [1024]u8 = undefined;
    var arr = std.io.fixedBufferStream(&buff);
    try bencode.root.encode(arr.writer());
    std.debug.print("{s}\n", .{arr.buffer[0..arr.pos]});

    try testing.expectEqualStrings(arr.buffer[0..arr.pos], data);
}
