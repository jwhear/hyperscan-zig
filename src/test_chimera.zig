const std = @import("std");
const ch = @import("chimera.zig");

test "compile and scan" {
    var error_info: ?*ch.CompileErrorInfo = null;
    var db = try ch.Database.compile("[0-9]+", ch.CompileFlags{ .caseless=true, .utf8=true},
                                     ch.CompileMode.no_groups, null, &error_info);
    defer db.free();

    var scratch = try ch.Scratch.init(db);
    defer scratch.free();

    var matches_found: usize = 0;
    const Callbacks = struct {
        pub fn onMatch(match: ch.MatchInfo, ctx: *usize) ch.CallbackResult {
            _ = match;
            ctx.* += 1;
            return ch.CallbackResult._continue;
        }
        pub fn onError(error_type: ch.ScanError, id: usize, ctx: *usize) ch.CallbackResult {
            _ = error_type;
            _ = id;
            _ = ctx;
            return ch.CallbackResult.terminate;
        }
    };

    try db.scan("a 12 b 13", &matches_found, &scratch, Callbacks.onMatch, Callbacks.onError);
    try std.testing.expectEqual(matches_found, 2);
}

test "compileMulti and scan" {
    var expressions = [_][*:0]const u8{
        "abc",
        "bab",
        "ddd"
    };

    const flag = ch.CompileFlags{.caseless=true, .utf8=true};
    var flags = [_]ch.CompileFlags{flag} ** 3;
    var ids = [_]u32{ 1,2,3 };

    var error_info: ?*ch.CompileErrorInfo = null;
    var db = try ch.Database.compileMulti(&expressions, &flags, &ids,
                                          ch.CompileMode.no_groups, null, &error_info);
    defer db.free();

    var scratch = try ch.Scratch.init(db);
    defer scratch.free();

    var matches_found: usize = 0;
    const Callbacks = struct {
        pub fn onMatch(match: ch.MatchInfo, ctx: *usize) ch.CallbackResult {
            _ = match;
            ctx.* += 1;
            return ch.CallbackResult._continue;
        }
        pub fn onError(error_type: ch.ScanError, id: usize, ctx: *usize) ch.CallbackResult {
            _ = error_type;
            _ = id;
            _ = ctx;
            return ch.CallbackResult.terminate;
        }
    };

    try db.scan("ab abc abab foo", &matches_found, &scratch, Callbacks.onMatch, Callbacks.onError);
    try std.testing.expectEqual(matches_found, 2);
}

test "print version" {
    std.debug.print("Chimera version {s}\n", .{ ch.version() });
}

test "info" {
    var error_info: ?*ch.CompileErrorInfo = null;
    var db = try ch.Database.compile("[0-9]+", ch.CompileFlags{ .caseless=true, .utf8=true},
                                     ch.CompileMode.no_groups, null, &error_info);
    defer db.free();
    std.debug.print("size = {}\n", .{ db.size() });
    std.debug.print("{s}\n", .{ db.info() });
}

test "compile error" {
    var error_info: ?*ch.CompileErrorInfo = null;
    var ret = ch.Database.compile("[0-9+", ch.CompileFlags{ .caseless=true, .utf8=true},
                                  ch.CompileMode.no_groups, null, &error_info);
    try std.testing.expectError(ch.ChimeraError.compiler, ret);
    if (error_info) |info| {
        std.debug.print("This error message is expected: {[message]s}, index={[expression]}\n", info.*);
        info.free();
    }
}
