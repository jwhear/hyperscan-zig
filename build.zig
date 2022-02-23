const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

pub const RuntimeType = enum {
    skinny,
    fat,
};

pub const generator = "Ninja";
pub const generator_cmd = "ninja";

pub fn build(b: *Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const chimera = try getChimeraStatic(b, RuntimeType.skinny);

    var main_tests = b.addTest("src/test_chimera.zig");
    main_tests.setBuildMode(mode);
    main_tests.linkLibC();
    main_tests.linkLibCpp();
    main_tests.addObjectFile(try std.fs.path.join(b.allocator, &[_][]const u8{chimera.lib_path, "libchimera.a"}));
    main_tests.addObjectFile(try std.fs.path.join(b.allocator, &[_][]const u8{chimera.lib_path, "libhs.a"}));
    main_tests.addObjectFile(try std.fs.path.join(b.allocator, &[_][]const u8{chimera.lib_path, "libpcre.a"}));
    main_tests.addIncludeDir(chimera.inc_path);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

//pub fn getHyperscan(b: *std.build.Builder) *LibExeObjStep {
//}

const CLib = struct {
    lib_path: []const u8,
    inc_path: []const u8,
};

/// Build libchimera and return the static library
pub fn getChimeraStatic(b: *Builder, rt: RuntimeType) !CLib {
    // Build hyperscan and get the .a file
    const chimera_dir = try buildHyperscan(b, true, rt);

    // Link libpcre into the lib dir
    const pcre_lib = try std.fs.path.join(b.allocator, &[_][]const u8{chimera_dir, "lib64", "libpcre.a"});
    if (!exists(pcre_lib)) {
        _ = try b.exec(&[_][]const u8{
            "link",
            try std.fs.path.join(b.allocator, &[_][]const u8{chimera_dir, "..", "lib", "libpcre.a"}),
            pcre_lib,
        });
    }

    return CLib{
        .lib_path=try std.fs.path.join(b.allocator, &[_][]const u8{chimera_dir, "lib64"}),
        .inc_path=try std.fs.path.join(b.allocator, &[_][]const u8{chimera_dir, "include"}),
    };
}

fn installHyperscanSource(b: *Builder, include_pcre: bool) ![]const u8 {
    const hyperscan_source = try std.fs.path.join(b.allocator, &[_][]const u8{
        b.global_cache_root, "hyperscan"
    });

    if (!exists(hyperscan_source)) {
        _ = try b.exec(&[_][]const u8{
            "git", "clone", "https://github.com/intel/hyperscan.git", hyperscan_source
        });
    }

    const pcre_source = try std.fs.path.join(b.allocator, &[_][]const u8{
        hyperscan_source, "pcre-8.41.tar.gz"
    });
    if (include_pcre and !exists(pcre_source)) {

        const pcre_archive = "pcre-8.41.tar.gz";

        // Chimera requires PCRE 8.41 source; see it's already present and, if not,
        //  download it
        _ = try b.exec(&[_][]const u8{
            "wget",
            "https://sourceforge.net/projects/pcre/files/pcre/8.41/pcre-8.41.tar.gz/download",
            try std.fmt.allocPrint(b.allocator, "-O{s}/{s}", .{hyperscan_source, pcre_archive})
        });

        _ = try b.exec(&[_][]const u8{
            "tar",
            try std.fmt.allocPrint(b.allocator, "--directory={s}", .{hyperscan_source}),
            "-xf",
            try std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ hyperscan_source, pcre_archive })
        });
    }
    return hyperscan_source;
}

fn buildHyperscan(b: *Builder, include_pcre: bool, rt: RuntimeType) ![]const u8 {
    const hyperscan_source = try installHyperscanSource(b, include_pcre);

    const build_name = try std.fmt.allocPrint(b.allocator, "build-{s}", .{@tagName(rt)});
    const build_dir = try std.fs.path.join(b.allocator, &[_][]const u8{
        hyperscan_source, build_name
    });


    // Run CMAKE
    _ = try b.exec(&[_][]const u8{
        "mkdir", "-p", build_dir
    });

    _ = try b.exec(&[_][]const u8{
        "cmake",
        "-B", build_dir,
        "-S", hyperscan_source,
        "-G", generator,
        // This flag deals with an error building PCRE
        "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON",

        if (rt == .skinny) "-DFAT_RUNTIME=off" else "-DFAT_RUNTIME=on",
        "-DCMAKE_C_COMPILER=zig-cc",
        "-DCMAKE_CXX_COMPILER=zig-c++",
        try std.fmt.allocPrint(b.allocator, "-DCMAKE_INSTALL_PREFIX={s}/install", .{ build_dir })
    });
    _ = try b.exec(&[_][]const u8{
        generator_cmd,
        "-C", build_dir,
        "install"
    });

    return std.fs.path.join(b.allocator, &[_][]const u8{ build_dir, "install" });
}

fn exists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{.read=true}) catch return false;
    return true;
}
