# zbencode
zig bencode library

# Example of usage

```zig
const std = @import("std");
const bencode = @import("bencode");
const bitorrent = @import("bitorrent/bitorrent.zig");
const fs = std.fs;
const print = std.debug.print;
const sizeFmt = std.fmt.fmtIntSizeBin;
const hexFmt = std.fmt.fmtSliceHexLower;

pub fn main() !void {
    // setup + args
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        print("usage: {s} [file.torrent]\n", .{args[0]});
        return;
    }

    // decoding
    const data = try fs.cwd().readFileAlloc(allocator, args[1], std.math.maxInt(usize));
    var bdata = try bencode.parse(allocator, data);
    defer bdata.deinit();
    allocator.free(data);

    // gather + show info from torrent file
    const root = bdata.root.dictionnary;
    const infos = root.get("info").?.dictionnary;
    const infohash: [20]u8 = try bitorrent.infohash(allocator, bdata.root);

    print("name    : {s}\n", .{infos.get("name").?.string});
    print("length  : {d}\n", .{sizeFmt(@intCast(infos.get("length").?.integer))});
    print("tracker : {s}\n", .{root.get("announce").?.string});
    print("creator : {s}\n", .{root.get("created by").?.string});
    print("created : {d}\n", .{root.get("creation date").?.integer});
    print("infohash: {s}\n", .{hexFmt(&infohash)});
}
```

> I am currently working on the bitorrent library
