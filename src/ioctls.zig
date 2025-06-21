const std = @import("std");

// Utils
const utils = @import("util.zig");
const debug2 = utils.debug2;
const debug = utils.debug;
const info = utils.info;
const error_ = utils.error_;
const contains = utils.contains;

// based on kernel code, found at:
// https://sites.uclouvain.be/SystInfo/usr/include/linux/input.h.html:
// https://elixir.bootlin.com/linux/v6.14/source/include/uapi/linux/input.h:
const EV_IOC_GNAME = 0x06;
const EV_IOC_GBITS_BASE = 0x20;
// https://elixir.bootlin.com/linux/v6.14/source/include/uapi/linux/input-event-codes.h:
const EV_MAX = 0x1f;
const EV_KEY_INDEX = 0x01;
const EV_MISC_INDEX = 0x04;
const KEY_MAX = 0x2ff;
// https://www.kernel.org/doc/Documentation/ioctl/ioctl-number.txt:
const IOC_INPUT_TYPE = 'E';

pub fn display_keyboard_device(device : std.fs.File) void {
    var res : [256]u8 = undefined;
    @memset(&res, 0);
    // based on https://sites.uclouvain.be/SystInfo/usr/include/linux/input.h.html
    const ioc = std.os.linux.IOCTL.IOR(IOC_INPUT_TYPE, EV_IOC_GNAME, @TypeOf(res));
    const ret = std.posix.system.ioctl(
        device.handle, 
        ioc, 
        @intFromPtr(&res),
    );
    if (ret < 0) {
        error_("ioctl EVIOCGNAME error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return;
    }
    info("Device Name: {s}", .{res});
}

fn get_bits(device : std.fs.File, event: u8, comptime T : type, res : *T) void {
    info ("Type: {}", .{T});
    @memset(res, 0);
    const ioc = std.os.linux.IOCTL.IOR(IOC_INPUT_TYPE, EV_IOC_GBITS_BASE + event, T);
    const ret = std.posix.system.ioctl(
        device.handle, 
        ioc, 
        @intFromPtr(res),
    );
    if (ret < 0) {
        error_("ioctl EVIOCGBITS error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return;
    }
}

fn get_event_bits(device : std.fs.File) void {
    var event_types : [EV_MAX]u8 = undefined;
    get_bits(device, 0, @TypeOf(event_types), &event_types);
    info("Device Event Bits: {X}", .{event_types});

    var keys : [KEY_MAX/64+1]u64= undefined;
    get_bits(device, EV_KEY_INDEX, @TypeOf(keys), &keys);
    info("Keys: {X}", .{keys});

    var misc : [KEY_MAX/64+1]u64 = undefined;
    get_bits(device, EV_MISC_INDEX, @TypeOf(misc), &misc);
    info("Misc: {X}", .{misc});

    return;
}

// consts based on: https://elixir.bootlin.com/linux/v6.14/source/include/uapi/linux/kd.h
const KbMode = enum(u32){
    RAW,
    XLATE,
    MEDIUM_RAW,
    UNICODE,
    OFF,
};

pub fn get_keyboard_mode(tty: std.fs.File) void {
    const KDGKBMODE : comptime_int = 0x4B44;
    var mode : KbMode = undefined;
    const ret = std.posix.system.ioctl(tty.handle, KDGKBMODE, @intFromPtr(&mode));

    if (ret < 0) {
        error_("ioctl KDGKBMODE error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return;
    }
    info("Keyboard Mode: {}", .{mode});
}

pub const KbTable = enum(u8){
    NORMAL,
    SHIFT,
    ALT,
    ALTSHIFT,
};

pub const KeyType = enum(u8){
    LATIN,
    FN,
    SPEC,
    PAD,
    DEAD,
    CONS,
    CUR,
    SHIFT,
    META,
    ASCII,
    LOCK,
    LETTER,
    SLOCK,
    DEAD2,
    BRL,
};

const KbEntry = packed struct {
    table: KbTable,
    index: u8,
    value: packed struct{
        value: u8,
        type: KeyType,
    },
};

pub fn get_keyboard_entry(tty: std.fs.File, code: u8, table: KbTable) void {
    const KDKBGENT : comptime_int = 0x4B46;
    var entry : KbEntry = .{
        .table = table, .index = code, .value = undefined
    };
    const ret = std.posix.system.ioctl(tty.handle, KDKBGENT, @intFromPtr(&entry));
    
    if (ret < 0) {
        error_("ioctl KDKBGENT  error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return 0;
    }
    info("Entry: {}", .{entry});
}

const KbKeycode = packed struct { 
    scancode: u32, 
    keycode: u32,
};

pub fn translate_sacncode_to_keycode(tty: std.fs.File, code: u32) u32 {
    const KDGETKEYCODE : comptime_int = 0x4B4C; // read kernel keycode table entry */
    var kbkeycode : KbKeycode = .{
        .scancode=code, .keycode=0,
    };
    const ret = std.posix.system.ioctl(tty.handle, KDGETKEYCODE, @intFromPtr(&kbkeycode));

    if (ret < 0) {
        error_("ioctl KDGETKEYCODE error_code: {d} | errno: {}", .{
            @as(i32, @bitCast(@as(u32, @truncate(ret)))),
            std.posix.errno(ret),
        });
        return 0;
    }
    info("Scan: {}", .{kbkeycode});
    return kbkeycode.keycode;
}
