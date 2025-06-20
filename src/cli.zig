const std = @import("std");
const utils = @import("util.zig");

const stdout = std.io.getStdOut().writer();

const CliErrors = error{
    FlagExpected,
    ValueExpected,
    UnkownFlag,
    ValueExists,
};

const Mode = enum {
    Flag,
    Value,
};

const Flag = enum {
    None, // for initialization and error handling
    Help,
    Verbose,
    VeryVerbose,
    Device,
};

const State = struct {
    mode: Mode, 
    flag: Flag,
};

const Arguments = struct {
    device_path: []u8,
};
pub var arguments : Arguments = undefined;
var _allocator: std.mem.Allocator = undefined;

pub fn free() void {
    _allocator.free(arguments.device_path);
}

pub fn print_arguments() void {
    utils.debug("Arguments: device => '{s}'", .{arguments.device_path});
}

inline fn check_flag(short: bool, flag_short: [:0]const u8, flag_long: [:0]const u8, arg: [:0]u8) bool {
    return (short and std.mem.eql(u8, flag_short, arg)) or std.mem.eql(u8, flag_long, arg);
}

fn help(prog_name: [:0]u8) void {
    stdout.print(
    \\usage: {s} [-d <device_path>] [-v[v]] [-h]
    \\
    \\      -d, --device           path to input device file (usually in the format: '/dev/input/eventX', 'X' being a number)
    \\      -v, --verbose          be verbose
    \\      -vv, --very-verbose    be very verbose (print a lot more of debug data)
    \\      -h, --help             display this help message
    \\
    ,.{prog_name}) catch {};
}

fn parse_flag(arg: [:0]u8) !State {
    if (arg.len < 2) {
        return .{ .mode=.Flag, .flag=.None};
    }

    var short: bool = undefined;
    if (std.mem.eql(u8, "--", arg[0..2])) {
        utils.debug2("fullname flag", .{});
        short = false;
    } else if (std.mem.eql(u8, "-", arg[0..1])) {
        utils.debug2("=> shortname flag", .{});
        short = true;
    } else {
        return CliErrors.FlagExpected;
    }

    if (check_flag(short, "-h", "--help", arg)) {
        return .{ .mode= .Flag, .flag= .Help};
    }
    if (check_flag(short, "-v", "--verbose", arg)) {
        return .{ .mode= .Flag, .flag= .Verbose};
    }
    if (check_flag(short, "-vv", "--very-verbose", arg)) {
        return .{ .mode= .Flag, .flag= .VeryVerbose};
    }
    if (check_flag(short, "-d", "--device", arg)) {
        return .{ .mode= .Value, .flag= .Device};
    }

    return CliErrors.UnkownFlag;
}

fn parse_value(arg: [:0]u8, flag:Flag) !State {
    if (arg.len < 1) {
        return .{ .mode=.Value, .flag=flag };
    }

    switch (flag) {
        .Device => {
            utils.debug("Setting Device: {s}", .{arg});
            if (arguments.device_path.len > 0) {
                return CliErrors.ValueExists;
            }
            arguments.device_path = _allocator.alloc(u8, arg.len) catch |err| {
                utils.error_("Failed to allocate arguments: {}", .{err});
                std.process.exit(1);
            };
            std.mem.copyForwards(u8, arguments.device_path, arg);
        },
        else => unreachable,
    }
    return .{ .mode=.Flag, .flag=flag };
}

fn switch_cli_errors(err: CliErrors, i: usize, arg: [:0]u8) State {
    switch (err) {
        CliErrors.ValueExpected => utils.error_(
            "Expected a Value, but found flag instead, at {d}: '{s}'", .{i, arg}
        ), 
        CliErrors.FlagExpected => utils.error_(
            "Expected a Flag, but found value instead, at {d}: '{s}'", .{i, arg}
        ),
        CliErrors.UnkownFlag => utils.error_(
            "Unknown Flag, at {d}: '{s}'", .{i, arg}
        ),
        CliErrors.ValueExists => utils.error_(
            "Given Value already exists, at {d}: '{s}'", .{i, arg}
        ),
    }
    return .{ .mode=.Flag, .flag=.None};
}

pub fn parse_command_line(allocator: std.mem.Allocator) !void {
    utils.set_verbose(0);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    _allocator = allocator;
    var prog_name: [:0]u8 = undefined;
    var state: State = .{ .mode = .Flag, .flag = .None };

    for (args, 0..) |arg, i| {
        utils.debug2("Current arg: '{s}'", .{arg});
        if (i == 0) {
            prog_name = arg;
            continue;
        }
        switch (state.mode) {
            .Flag => {
                state = parse_flag(arg) catch |err| switch_cli_errors(err, i, arg);
                switch (state.flag) {
                    .Verbose => utils.set_verbose(1),
                    .VeryVerbose => utils.set_verbose(2),
                    .Help => { help(prog_name); std.process.exit(0); },
                    .None => { std.process.exit(1); },
                    else => {},
                }
            },
            .Value => {
                state = parse_value(arg, state.flag) catch |err| switch_cli_errors(err, i, arg);
                switch (state.flag) {
                    .None => { std.process.exit(1); },
                    else => {},
                }
            },
        }
        utils.debug2("New state: {}\n", .{state});
    }
}
