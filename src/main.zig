const std = @import("std");
const linux = std.os.linux;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const Allocator = std.mem.Allocator;

// Utils
const utils = @import("util.zig");
const debug2 = utils.debug2;
const debug = utils.debug;
const info = utils.info;
const error_ = utils.error_;
const contains = utils.contains;

// Cli
const cli = @import("cli.zig");

// Keys
const KEY_EVENTS = @import("keys.zig").KEY_EVENTS;
const EVENT_TYPES = @import("keys.zig").EVENT_TYPES;
const KEYS = @import("keys.zig").KEYS;
const ioctls = @import("ioctls.zig");

// Constans
const BY_PATH_DIR = "/dev/input/by-path";

// Allocators
const MEM_SIZE : comptime_int = 1024*8; // 8 KB
var mem_buf : [MEM_SIZE:0]u8 = undefined;

// Errors
const ProgramError = error {
    NoKeboardSymlinkFound,
};

// Structures
const InputEvent = packed struct {
    time : packed struct {
        sec : std.posix.time_t,
        usec : std.posix.time_t,
    },
    type : EVENT_TYPES,
    code : KEYS,
    value : KEY_EVENTS,
};

// Program
fn find_keyboard_device(allocator : Allocator) ![]const u8 {
    info("Getting Keyboard Device", .{});
    debug("Searching keyboard device in: {s}", .{BY_PATH_DIR});
    const dir : std.fs.Dir = try std.fs.openDirAbsolute(BY_PATH_DIR, std.fs.Dir.OpenOptions{ .iterate = true, .no_follow = true });
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        debug("Checking: '{s}'", .{entry.basename});
        if (entry.kind != std.fs.File.Kind.sym_link) {
            debug("Skipping '{s}', not a symlink: {}", .{entry.basename, entry.kind});
            continue;
        } else if (!contains(u8, entry.basename, &.{"kbd", "keyboard"})){
            debug("Skipping '{s}', not a keyboard device", .{entry.basename});
            continue;
        }
        const symlink_path = try std.fs.path.join(allocator, &.{BY_PATH_DIR, entry.basename});
        defer allocator.free(symlink_path);
        var buf : [100:0]u8 = undefined; 
        const read = try std.posix.readlink(symlink_path, &buf);
        buf[read.len] = 0;
        const real_file_path = try std.fs.path.resolve(allocator, &.{BY_PATH_DIR, buf[0..read.len:0]});
        debug("Real path 1: {s}", .{real_file_path});
        return real_file_path;
    }
    return ProgramError.NoKeboardSymlinkFound;
}

fn loop_over_keyboard(device_path: []const u8) !void {
    debug("Looping over: '{s}'", .{device_path});
    const device = try std.fs.openFileAbsolute(device_path, .{ .mode = .read_only });
    defer device.close();
    debug("device handle: {}", .{device.handle});

    ioctls.display_keyboard_device(device);

    var poll_fds :[1]std.posix.pollfd = .{ 
    .{
        .fd = device.handle,
        .events = std.posix.POLL.IN,
        .revents = undefined,
    }};

    const buf_size : comptime_int = @bitSizeOf(InputEvent)/@bitSizeOf(u8);
    var buffer: [buf_size]u8 = undefined;
    while (true) {
        debug2("Polling device", .{});
        _ = try std.posix.poll(poll_fds[0..], -1);
        debug2("Readin device", .{});
        _ = try device.read(&buffer);
        debug2("Read event: {} bytes", .{buffer.len});
        var event : InputEvent = undefined; 
        event = std.mem.bytesToValue(InputEvent, &buffer);

        if (event.type != EVENT_TYPES.EV_KEY) {
            debug("Skipping event by type: {}", .{event.type});
            continue;
        }
        if (event.value == KEY_EVENTS.RELEASE) {
            debug("Skipping event by value: {}", .{event.value});
            continue;
        }

        info("Event: type => {} || event => {} || value => {}", .{
            event.type, 
            event.value, 
            event.code,
        });
    }
}

pub fn main() !void {
    info("Starting", .{});

    debug("Setting Allocator", .{});
    var fba = std.heap.FixedBufferAllocator.init(&mem_buf);
    const allocator = fba.allocator();

    try cli.parse_command_line(allocator);
    defer cli.free();
    cli.print_arguments();
    
    // try to get from command line, otherwise search for one
    const device_path = if (cli.arguments.device_path.len > 0) 
                    cli.arguments.device_path
                else find_keyboard_device(allocator) catch |err| {
                    switch (err) {
                        ProgramError.NoKeboardSymlinkFound => error_("Failed to find keyboard symlink", .{}),
                        else => error_("{}", .{err}),
                    } 
                    return; 
                }; 

    info("Keyboard Device Path: '{s}'", .{device_path});
    loop_over_keyboard(device_path) catch |err| switch (err) {
        else => error_("{}", .{err}),
    }; return;
}

