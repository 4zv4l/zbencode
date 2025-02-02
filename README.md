# zbencode
zig bencode library

# Example of usage

```zig
const std = @import("std");
const bencode = @import("bencode");
const sizeFmt = std.fmt.fmtIntSizeBin;

pub fn main() !void {
    // setup + args
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        print("usage: {s} [file.torrent]\n", .{args[0]});
        return;
    }

    // read file + decoding
    const data = try std.fs.cwd().readFileAlloc(tally, "debian.torrent", 1 * 1024 * 1024);
    defer tally.free(data);
    var arena = std.heap.ArenaAllocator.init(tally);
    var bencode = try parse(&arena, data);
    defer bencode.deinit(&arena);

    // pretty print
    const root = bencode.dictionnary;
    const info = root.get("info").?.dictionnary;
    std.debug.print("name   : {}\n", .{info.get("name").?});
    std.debug.print("length : {}\n", .{sizeFmt(@intCast(info.get("length").?.integer))});
    std.debug.print("tracker: {}\n", .{root.get("announce").?});
    std.debug.print("creator: {}\n", .{root.get("created by").?});
    std.debug.print("created: {}\n", .{root.get("creation date").?});
```

```
$ btest debian.torrent
name   : debian-12.9.0-amd64-netinst.iso
length : 632MiB
tracker: http://bttracker.debian.org:6969/announce
creator: mktorrent 1.1
created: 1736599700
```
