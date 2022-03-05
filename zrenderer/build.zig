const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

pub const Options = struct {
    build_mode: std.builtin.Mode,
    target: std.zig.CrossTarget,
    enable_pix: bool,
    enable_dx_debug: bool,
    enable_dx_gpu_debug: bool,
    tracy: ?[]const u8,
};

pub fn build(b: *std.build.Builder) void {
    const enable_pix = b.option(bool, "enable-pix", "Enable PIX GPU events and markers") orelse false;
    const enable_dx_debug = b.option(
        bool,
        "enable-dx-debug",
        "Enable debug layer for D3D12, D2D1, DirectML and DXGI",
    ) orelse false;
    const enable_dx_gpu_debug = b.option(
        bool,
        "enable-dx-gpu-debug",
        "Enable GPU-based validation for D3D12",
    ) orelse false;
    const tracy = b.option([]const u8, "tracy", "Enable Tracy profiler integration (supply path to Tracy source)");

    const options = Options{
        .build_mode = b.standardReleaseOptions(),
        .target = b.standardTargetOptions(.{}),
        .enable_pix = enable_pix,
        .enable_dx_debug = enable_dx_debug,
        .enable_dx_gpu_debug = enable_dx_gpu_debug,
        .tracy = tracy,
    };

    buildGLTFConverter(b, options);
    buildRenderer(b, options);
}

pub fn buildRenderer(b: *Builder, options: Options) void {
    var exe = b.addExecutable("zrenderer", thisDir() ++ "/src/zrenderer.zig");

    exe.setBuildMode(options.build_mode);
    exe.setTarget(options.target);

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_pix", options.enable_pix);
    exe_options.addOption(bool, "enable_dx_debug", options.enable_dx_debug);
    exe_options.addOption(bool, "enable_dx_gpu_debug", options.enable_dx_gpu_debug);
    exe_options.addOption(bool, "enable_tracy", options.tracy != null);
    exe_options.addOption(bool, "enable_d2d", true);
    exe_options.addOption([]const u8, "content_dir", "content/");

    exe.addOptions("build_options", exe_options);

    b.installFile("libs/zwin32/bin/x64/D3D12Core.dll", "bin/d3d12/D3D12Core.dll");
    b.installFile("libs/zwin32/bin/x64/D3D12Core.pdb", "bin/d3d12/D3D12Core.pdb");
    b.installFile("libs/zwin32/bin/x64/D3D12SDKLayers.dll", "bin/d3d12/D3D12SDKLayers.dll");
    b.installFile("libs/zwin32/bin/x64/D3D12SDKLayers.pdb", "bin/d3d12/D3D12SDKLayers.pdb");

    const dxc_step = buildShaders(b);
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/content",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content",
    });
    install_content_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_content_step.step);

    if (options.tracy) |tracy_path| {
        const client_cpp = std.fs.path.join(
            b.allocator,
            &[_][]const u8{ tracy_path, "TracyClient.cpp" },
        ) catch unreachable;
        exe.addIncludeDir(tracy_path);
        exe.addCSourceFile(client_cpp, &[_][]const u8{
            "-DTRACY_ENABLE=1",
            "-fno-sanitize=undefined",
            "-D_WIN32_WINNT=0x601",
        });
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("dbghelp");
    }

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;
    exe.want_lto = false;

    const options_pkg = Pkg{
        .name = "build_options",
        .path = exe_options.getSource(),
    };

    const zwin32_pkg = Pkg{
        .name = "zwin32",
        .path = .{ .path = thisDir() ++ "/libs/zwin32/zwin32.zig" },
    };
    exe.addPackage(zwin32_pkg);

    const zmath_pkg = Pkg{
        .name = "zmath",
        .path = .{ .path = thisDir() ++ "/libs/zmath/zmath.zig" },
    };
    exe.addPackage(zmath_pkg);

    const ztracy_pkg = Pkg{
        .name = "ztracy",
        .path = .{ .path = thisDir() ++ "/libs/ztracy/src/ztracy.zig" },
        .dependencies = &[_]Pkg{options_pkg},
    };
    exe.addPackage(ztracy_pkg);
    @import("./libs/ztracy/build.zig").link(b, exe, .{ .tracy_path = options.tracy });

    const zd3d12_pkg = Pkg{
        .name = "zd3d12",
        .path = .{ .path = thisDir() ++ "/libs/zd3d12/src/zd3d12.zig" },
        .dependencies = &[_]Pkg{
            zwin32_pkg,
            ztracy_pkg,
            options_pkg,
        },
    };
    exe.addPackage(zd3d12_pkg);
    @import("./libs/zd3d12/build.zig").link(b, exe);

    const common_pkg = Pkg{
        .name = "common",
        .path = .{ .path = thisDir() ++ "/libs/common/src/common.zig" },
        .dependencies = &[_]Pkg{
            zwin32_pkg,
            zd3d12_pkg,
            ztracy_pkg,
            options_pkg,
        },
    };
    exe.addPackage(common_pkg);
    @import("./libs/common/build.zig").link(b, exe);

    const scene_pkg = Pkg{
        .name = "scene",
        .path = .{ .path = thisDir() ++ "/src/scene/scene.zig" },
        .dependencies = &[_]Pkg{
            zmath_pkg,
        },
    };
    exe.addPackage(scene_pkg);

    exe.install();
}

pub fn buildGLTFConverter(b: *Builder, options: Options) void {
    var exe = b.addExecutable("gltf_converter", thisDir() ++ "/src/gltf_converter.zig");
    exe.setBuildMode(options.build_mode);
    exe.setTarget(options.target);

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_tracy", options.tracy != null);

    exe.addOptions("build_options", exe_options);

    const install_content_step = b.addInstallDirectory(
        .{ .source_dir = "content", .install_dir = .{ .custom = "" }, .install_subdir = "bin/content" },
    );
    b.getInstallStep().dependOn(&install_content_step.step);

    if (options.tracy) |tracy_path| {
        const client_cpp = std.fs.path.join(
            b.allocator,
            &[_][]const u8{ tracy_path, "TracyClient.cpp" },
        ) catch unreachable;
        exe.addIncludeDir(tracy_path);
        exe.addCSourceFile(client_cpp, &[_][]const u8{
            "-DTRACY_ENABLE=1",
            "-fno-sanitize=undefined",
            "-D_WIN32_WINNT=0x601",
        });
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("dbghelp");
    }

    const options_pkg = Pkg{
        .name = "build_options",
        .path = exe_options.getSource(),
    };

    const ztracy_pkg = Pkg{
        .name = "ztracy",
        .path = .{ .path = "../3rd_party/zig-gamedev/libs/ztracy/src/ztracy.zig" },
        .dependencies = &[_]Pkg{options_pkg},
    };
    exe.addPackage(ztracy_pkg);

    const zmath_pkg = Pkg{
        .name = "zmath",
        .path = .{ .path = "../3rd_party/zig-gamedev/libs/zmath/zmath.zig" },
    };
    exe.addPackage(zmath_pkg);

    const scene_pkg = Pkg{
        .name = "scene",
        .path = .{ .path = thisDir() ++ "/src/scene/scene.zig" },
        .dependencies = &[_]Pkg{
            zmath_pkg,
        },
    };
    exe.addPackage(scene_pkg);

    const c_libs_path = "libs/common/src/c";
    exe.addIncludeDir(c_libs_path);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("imm32");

    exe.addCSourceFile(c_libs_path ++ "/cgltf.c", &.{""});

    exe.install();
}

fn buildShaders(b: *std.build.Builder) *std.build.Step {
    const dxc_step = b.step("zrenderer-dxc", "Build shaders for zrenderer");

    var dxc_command = makeDxcCmd(
        "libs/common/src/hlsl/common.hlsl",
        "vsImGui",
        "imgui.vs.cso",
        "vs",
        "PSO__IMGUI",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd(
        "libs/common/src/hlsl/common.hlsl",
        "psImGui",
        "imgui.ps.cso",
        "ps",
        "PSO__IMGUI",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "libs/common/src/hlsl/common.hlsl",
        "csGenerateMipmaps",
        "generate_mipmaps.cs.cso",
        "cs",
        "PSO__GENERATE_MIPMAPS",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    return dxc_step;
}

fn makeDxcCmd(
    comptime input_path: []const u8,
    comptime entry_point: []const u8,
    comptime output_filename: []const u8,
    comptime profile: []const u8,
    comptime define: []const u8,
) [9][]const u8 {
    const shader_ver = "6_6";
    const shader_dir = "content/shaders/";
    return [9][]const u8{
        thisDir() ++ "/libs/zwin32/bin/x64/dxc.exe",
        thisDir() ++ "/" ++ input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };
}

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
