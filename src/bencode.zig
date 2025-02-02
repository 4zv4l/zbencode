const std = @import("std");
const Allocator = std.mem.Allocator;
const List = std.ArrayList(Token);
const Map = std.StringArrayHashMapUnmanaged(Token);

const Stream = std.io.FixedBufferStream([]const u8);
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

    pub fn deinit(self: *Token, arena: *std.heap.ArenaAllocator) void {
        switch (self.*) {
            .integer => {},
            else => arena.deinit(),
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
fn parseInteger(stream: *Stream) !Token {
    var buff: [1024]u8 = undefined;
    if (try stream.reader().readByte() != 'i') return error.ExpectedIntegerStart; // skip i
    const num = stream.reader().readUntilDelimiter(&buff, 'e') catch return error.BadNumber;
    return Token{ .integer = try std.fmt.parseInt(i64, num, 10) };
}

// 3:foo
fn parseString(ally: std.mem.Allocator, stream: *Stream) !Token {
    var buff: [1024]u8 = undefined;
    const num = try stream.reader().readUntilDelimiter(&buff, ':');
    const len = try std.fmt.parseUnsigned(usize, num, 10);

    const string = try ally.alloc(u8, len);
    errdefer ally.free(string);
    _ = try stream.read(string);
    return Token{ .string = string };
}

// li34e3:Fooe
fn parseList(ally: std.mem.Allocator, stream: *Stream) !Token {
    var list = List.init(ally);
    errdefer list.deinit();

    if (try stream.reader().readByte() != 'l') return error.ExpectedListStart; // skip l

    while (try stream.reader().readByte() != 'e') {
        try stream.seekTo(stream.pos - 1);
        try list.append(try parseAny(ally, stream));
    }

    return Token{ .list = list };
}

// d3:Foo133ee
fn parseDictionnary(ally: std.mem.Allocator, stream: *Stream) !Token {
    var map = Map{};
    if (try stream.reader().readByte() != 'd') return error.ExpectedDictionnaryStart; // skip d

    while (try stream.reader().readByte() != 'e') {
        try stream.seekTo(stream.pos - 1);
        const k = try parseString(ally, stream);
        const v = try parseAny(ally, stream);
        try map.put(ally, k.string, v);
    }
    return Token{ .dictionnary = map };
}

fn parseAny(ally: std.mem.Allocator, stream: *Stream) anyerror!Token {
    const c = try stream.reader().readByte();
    try stream.seekTo(stream.pos - 1);

    return switch (c) {
        'i' => try parseInteger(stream),
        '-', '0'...'9' => try parseString(ally, stream),
        'l' => try parseList(ally, stream),
        'd' => try parseDictionnary(ally, stream),
        else => return error.InvalidDelimiter,
    };
}

// call Token.deinit() to free the data
pub fn parse(arena: *std.heap.ArenaAllocator, data: []const u8) !Token {
    var stream: Stream = std.io.fixedBufferStream(data);
    return try parseAny(arena.allocator(), &stream);
}

///// TEST

const testing = std.testing;
const tally = testing.allocator;
const fixedBufferStream = std.io.fixedBufferStream;

test parseInteger {
    const data = "i34e";
    var buffstream = fixedBufferStream(data);
    const tk = try parseInteger(&buffstream);
    try testing.expect(tk == .integer);
    try testing.expectEqual(tk.integer, 34);
}

test parseString {
    const data = "3:Foo";
    var buffstream = fixedBufferStream(data);
    const tk = try parseString(tally, &buffstream);
    defer testing.allocator.free(tk.string);
    try testing.expect(tk == .string);
    try testing.expectEqualStrings(tk.string, "Foo");
}

test parseList {
    const data = "li34e3:Fooe";
    var arena = std.heap.ArenaAllocator.init(tally);
    var buffstream = fixedBufferStream(data);
    var tk = try parseList(arena.allocator(), &buffstream);
    defer tk.deinit(&arena);
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parseDictionnary {
    const data = "d3:Foo3:Bar3:Bari33ee";
    var arena = std.heap.ArenaAllocator.init(tally);
    var buffstream = fixedBufferStream(data);
    var tk = try parseDictionnary(arena.allocator(), &buffstream);
    defer tk.deinit(&arena);
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parseAny {
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ei35eee";
    var arena = std.heap.ArenaAllocator.init(tally);
    var buffstream = fixedBufferStream(data);
    var tk = try parseAny(arena.allocator(), &buffstream);
    defer tk.deinit(&arena);
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{tk});
}

test parse {
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ed5:Hello5:Worldeee";
    var arena = std.heap.ArenaAllocator.init(tally);
    var bencode = try parse(&arena, data);
    defer bencode.deinit(&arena);
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{bencode});
}

test "encode" {
    // create data structure
    const data = "d3:Foo3:Bar3:Bari33e4:Listli33ei34ed5:Hello5:Worldeee";
    var arena = std.heap.ArenaAllocator.init(tally);
    var bencode = try parse(&arena, data);
    defer bencode.deinit(&arena);
    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{bencode});

    // encode it
    var buff: [1024]u8 = undefined;
    var arr = std.io.fixedBufferStream(&buff);
    try bencode.encode(arr.writer());
    std.debug.print("{s}\n\n", .{arr.buffer[0..arr.pos]});

    try testing.expectEqualStrings(arr.buffer[0..arr.pos], data);
}

const sizeFmt = std.fmt.fmtIntSizeBin;
test "torrent file" {
    const data = try std.fs.cwd().readFileAlloc(tally, "debian.torrent", 1 * 1024 * 1024);
    defer tally.free(data);
    var arena = std.heap.ArenaAllocator.init(tally);
    var bencode = try parse(&arena, data);
    defer bencode.deinit(&arena);

    const root = bencode.dictionnary;
    const info = (root.get("info") orelse return error.NoInfoField).dictionnary;
    std.debug.print("name   : {}\n", .{info.get("name") orelse return error.NoNameField});
    std.debug.print("length : {}\n", .{sizeFmt(@intCast((info.get("length") orelse return error.NoLengthField).integer))});
    std.debug.print("tracker: {}\n", .{root.get("announce") orelse return error.NoAnnounceField});
    std.debug.print("creator: {}\n", .{root.get("created by") orelse return error.NoCreatedByField});
    std.debug.print("created: {}\n", .{root.get("creation date") orelse return error.NoCreationDateField});
}
