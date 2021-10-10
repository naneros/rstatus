const std = @import("std");
const dt = @import("dt.zig");

const stdout = std.io.getStdOut().writer();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = &gpa.allocator;

var jsonStrs: [7][]u8 = undefined;
var cpuA = [4]f64{ 0, 0, 0, 0 };
var cpuB = [4]f64{ 0, 0, 0, 0 };

var BLACK = "#000000".*;
var WHITE = "#ffffff".*;
var RED = "#d11141".*;
var GREEN = "#43b581".*;
var BLUE = "#9ecee6".*;
var YELLOW = "#d4af37".*;

const Block = struct {
    full_text: []u8 = "",
    color: []u8 = BLUE[0..BLUE.len],
    background: []u8 = BLACK[0..BLACK.len],
    border: []u8 = BLACK[0..BLACK.len],
    min_width: []u8 = "",
    urgent: bool = false,
    separator: bool = true,
};

pub fn main() !void {
    try proc();
}

fn winNameBlock(x: u8) !void {
    var block = Block{ .color = YELLOW[0..YELLOW.len] };
    const WorkJson = struct { change: []u8 };
    const WinJson = struct { change: []u8, container: struct { focused: bool, name: ?[]u8 } };
    const jsonOpc = .{ .allocator = allocator, .ignore_unknown_fields = true };
    const socket = try std.net.connectUnixSocket(std.os.getenv("I3SOCK").?);
    defer socket.close();

    const msg = "i3-ipc" ++ [_]u8{ 22, 0, 0, 0, 2, 0, 0, 0 } ++ "[\"window\",\"workspace\"]";

    try socket.writer().writeAll(msg);
    const reader = socket.reader();

    var magic: [6]u8 = undefined;
    while (true) {
        const b = try reader.readByte();

        magic[0] = magic[1];
        magic[1] = magic[2];
        magic[2] = magic[3];
        magic[3] = magic[4];
        magic[4] = magic[5];
        magic[5] = b;

        if (std.mem.eql(u8, &magic, "i3-ipc")) {
            const long = try reader.readIntNative(u32);
            const tipo = try reader.readIntNative(u16);
            _ = try reader.readIntNative(u16);

            const buf = try allocator.alloc(u8, long);
            defer allocator.free(buf);
            try reader.readNoEof(buf);

            if (tipo == 0) {
                var stream = std.json.TokenStream.init(buf);
                const res = try std.json.parse(WorkJson, &stream, jsonOpc);
                defer std.json.parseFree(WorkJson, res, jsonOpc);

                if (std.mem.eql(u8, res.change, "init")) {
                    block.full_text = try std.fmt.allocPrint(allocator, "", .{});
                }
            } else if (tipo == 3) {
                std.debug.print("\n\n-{s}-\n\n", .{buf});

                var stream = std.json.TokenStream.init(buf);
                const res = try std.json.parse(WinJson, &stream, jsonOpc);
                defer std.json.parseFree(WinJson, res, jsonOpc);

                std.debug.print("\n\n-{s}-\n\n", .{res.container.name});
                if (std.mem.eql(u8, res.change, "close") and res.container.focused) {
                    block.full_text = try std.fmt.allocPrint(allocator, "", .{});
                }
                if ((std.mem.eql(u8, res.change, "focus") or std.mem.eql(u8, res.change, "title")) and res.container.focused) {
                    block.full_text = try std.fmt.allocPrint(allocator, "{s}", .{res.container.name});
                }
            }
            var string = std.ArrayList(u8).init(allocator);
            try std.json.stringify(block, .{}, string.writer());
            jsonStrs[0] = string.items;
            try stdoutStatus();
        }
    }
}

fn stdoutStatus() !void {
    try stdout.print(",[{s},{s},{s},{s},{s},{s}]", .{
        jsonStrs[0],
        jsonStrs[1],
        jsonStrs[2],
        jsonStrs[3],
        jsonStrs[4],
        jsonStrs[5],
    });
}

fn proc() !void {
    for (jsonStrs) |item, index| {
        jsonStrs[index] = try std.fmt.allocPrint(allocator, "{{}}", .{});
    }

    const thread = try std.Thread.spawn(winNameBlock, @as(u8, 1));

    try stdout.print("{{ \"version\": 1 }}\n", .{});
    try stdout.print("[\n", .{});
    try stdout.print("[]\n", .{});

    while (true) {
        jsonStrs[1] = try kernelBlock();
        jsonStrs[2] = try vpnBlock();
        jsonStrs[3] = try memInfoBlock();
        jsonStrs[4] = try cpuBlock();
        jsonStrs[5] = try dateTimeBlock();

        try stdoutStatus();

        std.time.sleep(std.time.ns_per_s * 2);
    }
}

fn dateTimeBlock() ![]u8 {
    var dateTime = dt.timestamp2DateTime(dt.unix2local(std.time.timestamp()));
    var block = Block{
        .full_text = try std.fmt.allocPrint(allocator, "{:0>2}:{:0>2}", .{ dateTime.hour, dateTime.minute }),
    };
    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(block, .{}, string.writer());
    return string.items;
}

fn vpnBlock() ![]u8 {
    var block = Block{
        .full_text = try std.fmt.allocPrint(allocator, "VPN", .{}),
        .color = BLACK[0..BLACK.len],
        .background = GREEN[0..GREEN.len],
    };

    _ = std.fs.openDirAbsolute("/sys/class/net/tun0", .{}) catch |err| {
        block.color = WHITE[0..WHITE.len];
        block.background = RED[0..RED.len];
    };

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(block, .{}, string.writer());
    return string.items;
}

fn cpuBlock() ![]u8 {
    const f = try std.fs.cwd().openFile("/proc/stat", .{});
    defer f.close();

    const r = f.reader();
    var buf: [1024]u8 = undefined;
    const line = try r.readUntilDelimiterOrEof(&buf, '\n');
    var iter = std.mem.tokenize(line.?, " ");
    _ = iter.next();
    cpuB[0] = try std.fmt.parseFloat(f64, iter.next().?);
    cpuB[1] = try std.fmt.parseFloat(f64, iter.next().?);
    cpuB[2] = try std.fmt.parseFloat(f64, iter.next().?);
    cpuB[3] = try std.fmt.parseFloat(f64, iter.next().?);

    const sumB1 = cpuB[0] + cpuB[1] + cpuB[2];
    const sumA1 = cpuA[0] + cpuA[1] + cpuA[2];
    const sumB2 = cpuB[0] + cpuB[1] + cpuB[2] + cpuB[3];
    const sumA2 = cpuA[0] + cpuA[1] + cpuA[2] + cpuA[3];
    const cpuLoadAvg = ((sumB1 - sumA1) / (sumB2 - sumA2)) * 100;

    cpuA[0] = cpuB[0];
    cpuA[1] = cpuB[1];
    cpuA[2] = cpuB[2];
    cpuA[3] = cpuB[3];

    var block = Block{
        .full_text = try std.fmt.allocPrint(allocator, "{d:.2}%", .{cpuLoadAvg}),
    };

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(block, .{}, string.writer());
    return string.items;
}

fn kernelBlock() ![]u8 {
    const f = try std.fs.cwd().openFile("/proc/version", .{});
    defer f.close();

    const r = f.reader();
    var buf: [1024]u8 = undefined;
    const line = try r.readUntilDelimiterOrEof(&buf, '\n');
    var iter = std.mem.tokenize(line.?, " ");
    _ = iter.next();
    _ = iter.next();
    var ver = iter.next();

    var block = Block{
        .full_text = try std.fmt.allocPrint(allocator, "{s}", .{ver}),
    };

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(block, .{}, string.writer());
    return string.items;
}

fn memInfoBlock() ![]u8 {
    const f = try std.fs.cwd().openFile("/proc/meminfo", .{});
    defer f.close();

    const r = f.reader();
    var memTotal: u32 = 0;
    var memAval: u32 = 0;
    var memUsed: u32 = 0;

    var buf: [1024]u8 = undefined;
    while (try r.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var iter = std.mem.tokenize(line, " ");

        while (iter.next()) |item| {
            if (std.mem.eql(u8, item, "MemTotal:")) {
                memTotal = try std.fmt.parseInt(u32, iter.next().?, 10);
            }
            if (std.mem.eql(u8, item, "MemAvailable:")) {
                memAval = try std.fmt.parseInt(u32, iter.next().?, 10);
            }
        }
        memUsed = (memTotal - memAval) / 1024;
    }

    var block = Block{
        .full_text = try std.fmt.allocPrint(allocator, "{d}K", .{memUsed}),
    };

    var string = std.ArrayList(u8).init(allocator);
    try std.json.stringify(block, .{}, string.writer());
    return string.items;
}
