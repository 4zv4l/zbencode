# zbencode
zig bencode library

# Example of usage

```zig
const std = @import("std");
const bencode = @import("bencode");
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

    // show info from torrent file
    const root = bdata.root.dictionnary;
    const infos = root.get("info").?.dictionnary;

    print("name    : {}\n", .{infos.get("name").?});
    print("length  : {}\n", .{sizeFmt(@intCast(infos.get("length").?.integer))});
    print("tracker : {}\n", .{root.get("announce").?});
    print("creator : {}\n", .{root.get("created by").?});
    print("created : {}\n", .{root.get("creation date").?});
}
```

```
$ btest debian-12.6.0-amd64-netinst.iso.torrent
name    : debian-12.6.0-amd64-netinst.iso
length  : 631MiB
tracker : http://bttracker.debian.org:6969/announce
creator : mktorrent 1.1
created : 1719662085
```
