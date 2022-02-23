const std = @import("std");
const c = @cImport({
    @cInclude("hs/ch.h");
});

///
pub const CompileFlags = packed struct {
    /// Matching will be performed case-insensitively
    caseless: bool = false,
    /// Matching a . will not exclude newlines.
    dot_all: bool = false,
    /// ^ and $ anchors match any newlines in data.
    multiline: bool = false,
    /// Only one match will be generated for the expression per stream.
    single_match: bool = false,

    _padding1: bool = false, // bit 5 is unused

    /// Treat this pattern as a sequence of UTF-8 characters.
    utf8: bool = false,
    /// Use Unicode properties for character classes.
    ucp: bool = false,

    _padding2: i25 align(4) = 0, // pad out to 32bits (same as c_uint)

    /// Cast this CompileFlags to a c_uint
    pub fn toC(self: CompileFlags) c_uint {
        return @bitCast(c_uint, self);
    }
};

///
pub const CompileMode = enum(c_uint) {
    ///
    no_groups = c.CH_MODE_NOGROUPS,
    ///
    groups = c.CH_MODE_GROUPS,
};

///
pub const PlatformInfo = c.hs_platform_info;

///
pub const CompileErrorInfo = extern struct {
    /// A human-readable error message describing the error.
    message: [*:0]u8,

    /// The zero-based number of the expression that caused the error (if this
    ///  can be determined). If the error is not specific to an expression, then
    ///  this value will be less than zero.
    expression: c_int,

    ///
    pub fn free(self: *CompileErrorInfo) void {
        _ = c.ch_free_compile_error(@ptrCast(*c.ch_compile_error_t, self));
    }
};

///
pub const ChimeraError = error{
    /// The engine completed normally.
    //success = c.CH_SUCCESS

    /// A parameter passed to this function was invalid.
    invalid,

    /// A memory allocation failed.
    no_memory,

    /// The engine was terminated by callback.
    /// This return value indicates that the target buffer was partially scanned, but that the callback function requested that scanning cease after a match was located.
    //scan_terminated = c.CH_SCAN_TERMINATED

    /// The pattern compiler failed, and the ch_compile_error_t should be inspected for more detail.
    compiler,

    /// The given database was built for a different version of the Chimera matcher.
    db_version,

    /// The given database was built for a different platform (i.e., CPU type).
    db_platform,

    /// The given database was built for a different mode of operation. This error is returned when streaming calls are used with a non-streaming database and vice versa.
    db_mode,

    /// A parameter passed to this function was not correctly aligned.
    bad_align,

    /// The memory allocator did not correctly return memory suitably aligned for the largest representable data type on this platform.
    bad_alloc,

    /// The scratch region was already in use.
    ///
    /// This error is returned when Chimera is able to detect that the scratch region given is already in use by another Chimera API call.
    ///
    /// A separate scratch region, allocated with ch_alloc_scratch() or ch_clone_scratch(), is required for every concurrent caller of the Chimera API.
    ///
    /// For example, this error might be returned when ch_scan() has been called inside a callback delivered by a currently-executing ch_scan() call using the same scratch region.
    ///
    /// Note: Not all concurrent uses of scratch regions may be detected. This error is intended as a best-effort debugging tool, not a guarantee.
    scratch_in_use,

    /// Unexpected internal error from Hyperscan.
    ///
    /// This error indicates that there was unexpected matching behaviors from Hyperscan. This could be related to invalid usage of scratch space or invalid memory operations by users.
    unknown,

    /// Returned when pcre_exec (called for some expressions internally from ch_scan) failed due to a fatal error.
    internal,
};

///
pub const CallbackResult = enum(c_int) {
    ///Continue matching.
    _continue = c.CH_CALLBACK_CONTINUE,

    ///Terminate matching.
    terminate = c.CH_CALLBACK_TERMINATE,

    ///Skip remaining matches for this ID and continue.
    skip_pattern = c.CH_CALLBACK_SKIP_PATTERN,
};

///
pub const ScanError = enum(c_int) {

    ///PCRE hits its match limit and reports PCRE_ERROR_MATCHLIMIT.
    match_limit = c.CH_ERROR_MATCHLIMIT,

    ///PCRE hits its recursion limit and reports PCRE_ERROR_RECURSIONLIMIT.
    recursion_limit = c.CH_ERROR_RECURSIONLIMIT,
};

///
pub const ScanFlag = enum(c_uint) {
    ///Flag indicating that a particular capture group is inactive, used in ch_capture_t::flags.
    flag_inactive = c.CH_CAPTURE_FLAG_INACTIVE,

    ///Flag indicating that a particular capture group is active, used in ch_capture_t::flags.
    flag_active = c.CH_CAPTURE_FLAG_ACTIVE,
};

///
pub fn translateError(err: c.ch_error_t) !void {
    return switch (err) {
        c.CH_SUCCESS, c.CH_SCAN_TERMINATED => {},
        c.CH_INVALID => ChimeraError.invalid,
        c.CH_NOMEM => ChimeraError.no_memory,
        c.CH_COMPILER_ERROR => ChimeraError.compiler,
        c.CH_DB_VERSION_ERROR => ChimeraError.db_version,
        c.CH_DB_PLATFORM_ERROR => ChimeraError.db_platform,
        c.CH_DB_MODE_ERROR => ChimeraError.db_mode,
        c.CH_BAD_ALIGN => ChimeraError.bad_align,
        c.CH_BAD_ALLOC => ChimeraError.bad_alloc,
        c.CH_SCRATCH_IN_USE => ChimeraError.scratch_in_use,
        c.CH_FAIL_INTERNAL => ChimeraError.internal,
        else => ChimeraError.unknown,
    };
}

///
pub const MatchEventHandlerRaw = fn (expression_id: c_uint, from_byte: c_ulonglong, to_byte: c_ulonglong, flags: c_uint, size: c_uint, captured: [*c]const Capture, ctx: ?*anyopaque) callconv(.C) c_int;

///
pub const ErrorEventHandlerRaw = fn (error_type: c_int, id: c_uint, info: ?*anyopaque, ctx: ?*anyopaque) callconv(.C) c_int;

/// fn(info: MatchInfo, ctx: <Context>) CallbackResult
pub fn MatchEventHandler(comptime Context: type) type {
    return fn (MatchInfo, Context) CallbackResult;
}

/// fn(error_type: ScanError, id: usize, ctx: <Context>) CallbackResult
pub fn ErrorEventHandler(comptime Context: type) type {
    return fn (error_type: ScanError, id: usize, ctx: Context) CallbackResult;
}

///
pub const Database = struct {
    ///
    handle: ?*c.ch_database_t,

    /// Compiles `expression` into a database.
    /// If `platform` is null, the database is tuned for the current platform.
    /// If compilation fails an error will be returned and
    ///  `inf` will be initialized to a `CompileErrorInfo` assuming you didn't
    ///  pass null for that parameter.
    pub fn compile(expression: [:0]const u8, flags: CompileFlags, mode: CompileMode, platform: ?*PlatformInfo, inf: *?*CompileErrorInfo) !Database {
        var ret: Database = undefined;
        const st = c.ch_compile(expression.ptr, flags.toC(), @enumToInt(mode), platform, &ret.handle, @ptrCast(*?*c.ch_compile_error_t, inf));
        try translateError(st);
        return ret;
    }

    /// Compile `expressions` into a database, with a `CompileFlags` and id for
    ///  each expression.  If compilation fails an error will be returned and
    ///  `inf` will be initialized to a `CompileErrorInfo` assuming you didn't
    ///  pass null for that parameter.
    /// Expects `expression.len == flags.len == ids.len`
    /// `ids` do not need to be unique, these values can be whatever you like
    ///  and are what are provided in the match handler as `MatchInfo.id`.
    pub fn compileMulti(expressions: [][*:0]const u8, flags: []CompileFlags, ids: []u32, mode: CompileMode, platform: ?*PlatformInfo, inf: *?*CompileErrorInfo) !Database {
        std.debug.assert(expressions.len == flags.len);
        std.debug.assert(expressions.len == ids.len);

        var ret: Database = undefined;
        const st = c.ch_compile_multi(@ptrCast([*]const [*]const u8, expressions.ptr), @ptrCast([*]const c_uint, flags.ptr), ids.ptr, @intCast(c_uint, expressions.len), @enumToInt(mode), platform, &ret.handle, @ptrCast(*?*c.ch_compile_error_t, inf));
        try translateError(st);
        return ret;
    }

    ///
    pub fn compileExtMulti(expressions: [][*:0]const u8, flags: []CompileFlags, ids: []u32, mode: CompileMode, match_limit: c_ulong, match_limit_recursion: c_ulong, platform: ?*PlatformInfo, inf: *?*CompileErrorInfo) !Database {
        std.debug.assert(expressions.len == flags.len);
        std.debug.assert(expressions.len == ids.len);

        var ret: Database = undefined;
        const st = c.ch_compile_ext_multi(@ptrCast([*]const [*]const u8, expressions.ptr), @ptrCast([*]const c_uint, flags.ptr), ids.ptr, @intCast(c_uint, expressions.len), @enumToInt(mode), match_limit, match_limit_recursion, platform, &ret.handle, @ptrCast(*?*c.ch_compile_error_t, inf));
        try translateError(st);
        return ret;
    }

    ///
    pub fn free(self: *Database) void {
        //TODO not sure what failure cases exist; would prefer to have free never fail
        _ = c.ch_free_database(self.handle);
    }

    /// Note: the `flags` parameter is skipped unused and skipped intentionally
    pub fn scanRaw(self: *const Database, data: []const u8, scratch: *Scratch, on_event: MatchEventHandlerRaw, on_error: ErrorEventHandlerRaw, context: anytype) !void {
        if (data.len > std.math.maxInt(c_uint)) return error.data_too_large;
        const err = c.ch_scan(self.handle, data.ptr, @intCast(c_uint, data.len), 0, // unused flags param
            scratch.handle, on_event, on_error, context);

        try translateError(err);
    }

    ///
    pub fn scan(self: *const Database, data: []const u8, context: anytype, scratch: *Scratch, on_event: MatchEventHandler(@TypeOf(context)), on_error: ErrorEventHandler(@TypeOf(context))) !void {
        //TODO ensure that context is a pointer type

        if (data.len > std.math.maxInt(c_uint)) return error.data_too_large;

        const Closure = WrapClosure(@TypeOf(context));
        var closure = Closure{
            .match_func = on_event,
            .err_func = on_error,
            .context = context,
        };

        return self.scanRaw(data, scratch, Closure.onMatch, Closure.onError, &closure);
    }

    /// Returns the size of this database
    pub fn size(self: *Database) !usize {
        var ret: usize = undefined;
        try translateError(c.ch_database_size(self.handle, &ret));
        return ret;
    }

    /// Returns the info about this database.  The result should be freed with
    ///  the current allocator.
    pub fn info(self: *Database) ![]const u8 {
        var ret: [*c]u8 = undefined;
        try translateError(c.ch_database_info(self.handle, &ret));
        return std.mem.span(ret);
    }
};

///
pub const Scratch = struct {
    handle: ?*c.ch_scratch_t = null,

    /// Creates a Scratch space large enough to be used with `db.scan()`
    /// You may call additionally call `alloc` with other databases subsequently.
    pub fn init(db: Database) !Scratch {
        var ret = Scratch{};
        try ret.alloc(db);
        return ret;
    }

    ///
    pub fn free(self: *Scratch) void {
        //TODO error?
        _ = c.ch_free_scratch(self.handle);
    }

    /// Ensures that this scratch space is large enough to support `db`
    /// You may call this method repeatedly with different databases.
    pub fn alloc(self: *Scratch, db: Database) !void {
        const err = c.ch_alloc_scratch(db.handle, &self.handle);
        try translateError(err);
    }

    /// Produces a new scratch space by cloning an existing one
    pub fn clone(self: *Scratch) !Scratch {
        var ret = Scratch{};
        const err = c.ch_clone_scratch(self.handle, &ret.handle);
        try translateError(err);
        return ret;
    }

    /// Provides the size of the given scratch space.
    pub fn size(self: *const Scratch) !usize {
        var ret: usize = undefined;
        try translateError(self.handle, &ret);
        return ret;
    }
};

///
pub const Capture = c.ch_capture;

///
pub const MatchInfo = struct {
    ///
    id: u32,
    ///
    from: usize,
    ///
    to: usize,
    ///
    flags: u32,
    ///
    captures: []const Capture,
};

// The actual Chimera callback function types are a pain to use in Zig, e.g.:
//
// fn onMatch(expression_id: c_uint,
//            from_byte: c_ulonglong, to_byte: c_ulonglong,
//            flags: c_uint, size: c_uint,
//            captured: [*c]const Capture,
//            ctx: ?*c_void) callconv(.C) c_int
// {
//     _ = flags;
//     // etc. for all unused params
//     var real_context = @ptrCast(*MyContextType, @alignCast(ctx));
//     // Do stuff
//     return @intCast(CallbackResult._continue);
// }
//
// This type makes wraps with a layer of indirection and allows much simpler,
//  zig-native callbacks
fn WrapClosure(comptime Context: type) type {
    return struct {
        match_func: MatchEventHandler(Context),
        err_func: ErrorEventHandler(Context),
        context: Context,

        const Self = @This();

        pub fn onMatch(id: c_uint, from: c_ulonglong, to: c_ulonglong, flags: c_uint, size: c_uint, captured: [*c]const Capture, ctx: ?*anyopaque) callconv(.C) c_int {
            const mi = MatchInfo{
                .id = @intCast(u32, id),
                .from = @intCast(usize, from),
                .to = @intCast(usize, to),
                .flags = @intCast(u32, flags),
                .captures = captured[0..size],
            };
            var closure = @ptrCast(*Self, @alignCast(@alignOf(*Self), ctx));
            return @enumToInt(closure.match_func(mi, closure.context));
        }

        pub fn onError(error_type: c_int, id: c_uint, info: ?*anyopaque, ctx: ?*anyopaque) callconv(.C) c_int {
            _ = info;
            var closure = @ptrCast(*Self, @alignCast(@alignOf(*Self), ctx));
            return @enumToInt(closure.err_func(@intToEnum(ScanError, error_type), @intCast(usize, id), closure.context));
        }
    };
}

// In order to support using std.mem.Allocator with Chimera's set_allocator functions
//  we need to store the provided allocator somewhere because we don't have any way
//  to do a closure (no context parameter).
var global_allocator: ?*std.mem.Allocator = null;

fn globalAlloc(sz: usize) callconv(.C) ?*anyopaque {
    if (global_allocator) |a| {
        return a.allocAdvanced(u8, @alignOf(usize), sz, false) catch return null;
    } else @panic("No global allocator has been set");
}

fn globalFree(mem: [*]anyopaque) callconv(.C) void {
    if (global_allocator) |a| {
        a.free(mem);
    } else @panic("No global allocator has been set");
}

/// Configure allocators for various operations.
/// Note: there is no way to change the allocator used for temporary objects
///  created during the various compile calls (ch_compile() and ch_compile_multi()).
const Allocators = struct {

    ///
    pub const AllocFunc = fn (usize) callconv(.C) ?*anyopaque;
    ///
    pub const FreeFunc = fn (?*anyopaque) callconv(.C) void;

    ///
    pub fn setAllocatorFuncs(alloc: AllocFunc, free: FreeFunc) !void {
        try translateError(c.ch_set_allocator(alloc, free));
    }

    ///
    pub fn setDatabaseFuncs(alloc: AllocFunc, free: FreeFunc) !void {
        try translateError(c.ch_set_database_allocator(alloc, free));
    }

    ///
    pub fn setMiscFuncs(alloc: AllocFunc, free: FreeFunc) !void {
        try translateError(c.ch_set_misc_allocator(alloc, free));
    }

    ///
    pub fn setScratchFuncs(alloc: AllocFunc, free: FreeFunc) !void {
        try translateError(c.ch_set_scratch_allocator(alloc, free));
    }

    /// This sets all allocation/free functions globally using a Zig allocator
    pub fn setAllocator(allocator: *std.mem.Allocator) !void {
        global_allocator = allocator;
        setAllocatorFuncs(globalAlloc, globalFree);
    }
};

/// Returns the release version of Chimera. Do not free the result.
pub fn version() []const u8 {
    return std.mem.span(c.ch_version());
}
