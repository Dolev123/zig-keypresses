const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

var verbose : usize = 0;

pub fn set_verbose(v: usize) void {
    verbose = v;
}

pub fn debug2(comptime format: []const u8, args: anytype) void {
    if (verbose < 2) return;
    stderr.print("[ ] " ++ format ++ "\n", args) catch {};
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    if (verbose < 1) return;
    stderr.print("[ ] " ++ format ++ "\n", args) catch {};
}

pub fn info(comptime format: []const u8, args: anytype) void {
    stdout.print("[+] " ++ format ++ "\n", args) catch {};
}

pub fn error_(comptime format: []const u8, args: anytype) void {
    stderr.print("[!] " ++ format ++ "\n", args) catch {};
}

pub fn contains(comptime T: type, haystack: []const T, needles: []const[]const T) bool {
    for (needles) |needle| {
        _ = std.mem.indexOf(T, haystack, needle) orelse continue;
        return true;
    }
    return false;
}
