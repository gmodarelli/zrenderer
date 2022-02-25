const std = @import("std");
const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

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
        "../3rd_party/zig-gamedev/external/bin/dxc/dxc.exe",
        input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };
}

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

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_pix", enable_pix);
    exe_options.addOption(bool, "enable_dx_debug", enable_dx_debug);
    exe_options.addOption(bool, "enable_dx_gpu_debug", enable_dx_gpu_debug);
    exe_options.addOption(bool, "enable_tracy", tracy != null);

    b.installFile("../3rd_party/zig-gamedev/external/bin/d3d12/D3D12Core.dll", "bin/d3d12/D3D12Core.dll");
    b.installFile("../3rd_party/zig-gamedev/external/bin/d3d12/D3D12Core.pdb", "bin/d3d12/D3D12Core.pdb");
    b.installFile("../3rd_party/zig-gamedev/external/bin/d3d12/D3D12SDKLayers.dll", "bin/d3d12/D3D12SDKLayers.dll");
    b.installFile("../3rd_party/zig-gamedev/external/bin/d3d12/D3D12SDKLayers.pdb", "bin/d3d12/D3D12SDKLayers.pdb");
    const install_content_step = b.addInstallDirectory(
        .{ .source_dir = "content", .install_dir = .{ .custom = "" }, .install_subdir = "bin/content" },
    );
    b.getInstallStep().dependOn(&install_content_step.step);

    const dxc_step = b.step("dxc", "Build shaders");

    var dxc_command = makeDxcCmd("../3rd_party/zig-gamedev/libs/common/common.hlsl", "vsImGui", "imgui.vs.cso", "vs", "PSO__IMGUI");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("../3rd_party/zig-gamedev/libs/common/common.hlsl", "psImGui", "imgui.ps.cso", "ps", "PSO__IMGUI");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd(
        "../3rd_party/zig-gamedev/libs/common/common.hlsl",
        "csGenerateMipmaps",
        "generate_mipmaps.cs.cso",
        "cs",
        "PSO__GENERATE_MIPMAPS",
    );
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    install_content_step.step.dependOn(dxc_step);

    _ = buildMeshConverter(b, exe_options, tracy);

    // const Program = struct {
    //     exe: *std.build.LibExeObjStep,
    //     deps: struct {
    //         cgltf: bool = false,
    //     },
    // };

    // const progs = [_]Program{
    //     .{ .exe = b.addExecutable("zrenderer", "src/main.zig"), .deps = .{} },
    //     .{ .exe = b.addExecutable("mesh_converter", "src/tools/mesh_converter.zig"), .deps = .{ .cgltf = true } },
    // };
    // const active_prog = progs[0];
    // const target_options = b.standardTargetOptions(.{});
    // const release_options = b.standardReleaseOptions();

    // for (progs) |prog| {
    //     prog.exe.setBuildMode(release_options);
    //     prog.exe.setTarget(target_options);
    //     prog.exe.addOptions("build_options", exe_options);

    //     if (tracy) |tracy_path| {
    //         const client_cpp = std.fs.path.join(
    //             b.allocator,
    //             &[_][]const u8{ tracy_path, "TracyClient.cpp" },
    //         ) catch unreachable;
    //         prog.exe.addIncludeDir(tracy_path);
    //         prog.exe.addCSourceFile(client_cpp, &[_][]const u8{
    //             "-DTRACY_ENABLE=1",
    //             "-fno-sanitize=undefined",
    //             "-D_WIN32_WINNT=0x601",
    //         });
    //         prog.exe.linkSystemLibrary("ws2_32");
    //         prog.exe.linkSystemLibrary("dbghelp");
    //     }

    //     // This is needed to export symbols from an .exe file.
    //     // We export D3D12SDKVersion and D3D12SDKPath symbols which
    //     // is required by DirectX 12 Agility SDK.
    //     prog.exe.rdynamic = true;
    //     prog.exe.want_lto = false;

    //     const zwin32_pkg = Pkg{
    //         .name = "zwin32",
    //         .path = .{ .path = "../3rd_party/zig-gamedev/libs/zwin32/zwin32.zig" },
    //     };
    //     prog.exe.addPackage(zwin32_pkg);

    //     const options_pkg = Pkg{
    //         .name = "build_options",
    //         .path = exe_options.getSource(),
    //     };

    //     const ztracy_pkg = Pkg{
    //         .name = "ztracy",
    //         .path = .{ .path = "../3rd_party/zig-gamedev/libs/ztracy/ztracy.zig" },
    //         .dependencies = &[_]Pkg{options_pkg},
    //     };
    //     prog.exe.addPackage(ztracy_pkg);

    //     const zd3d12_pkg = Pkg{
    //         .name = "zd3d12",
    //         .path = .{ .path = "../3rd_party/zig-gamedev/libs/zd3d12/zd3d12.zig" },
    //         .dependencies = &[_]Pkg{
    //             zwin32_pkg,
    //             ztracy_pkg,
    //             options_pkg,
    //         },
    //     };
    //     prog.exe.addPackage(zd3d12_pkg);

    //     const zmath_pkg = Pkg{
    //         .name = "zmath",
    //         .path = .{ .path = "../3rd_party/zig-gamedev/libs/zmath/zmath.zig" },
    //     };
    //     prog.exe.addPackage(zmath_pkg);

    //     const common_pkg = Pkg{
    //         .name = "common",
    //         .path = .{ .path = "../3rd_party/zig-gamedev/libs/common/common.zig" },
    //         .dependencies = &[_]Pkg{
    //             zwin32_pkg,
    //             zd3d12_pkg,
    //             ztracy_pkg,
    //             options_pkg,
    //         },
    //     };
    //     prog.exe.addPackage(common_pkg);

    //     const external = "../3rd_party/zig-gamedev/external/src";
    //     prog.exe.addIncludeDir(external);

    //     prog.exe.linkSystemLibrary("c");
    //     prog.exe.linkSystemLibrary("c++");
    //     prog.exe.linkSystemLibrary("imm32");

    //     prog.exe.addCSourceFile(external ++ "/imgui/imgui.cpp", &.{""});
    //     prog.exe.addCSourceFile(external ++ "/imgui/imgui_widgets.cpp", &.{""});
    //     prog.exe.addCSourceFile(external ++ "/imgui/imgui_tables.cpp", &.{""});
    //     prog.exe.addCSourceFile(external ++ "/imgui/imgui_draw.cpp", &.{""});
    //     prog.exe.addCSourceFile(external ++ "/imgui/imgui_demo.cpp", &.{""});
    //     prog.exe.addCSourceFile(external ++ "/cimgui.cpp", &.{""});

    //     if (prog.deps.cgltf) {
    //         prog.exe.addCSourceFile(external ++ "/cgltf.c", &.{""});
    //     }

    //     prog.exe.install();
    // }

    // const run_cmd = meshConverterExe.run();
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
}

pub fn buildMeshConverter(b: *Builder, build_options: *std.build.OptionsStep, tracy: ?[]const u8) *std.build.LibExeObjStep {
    const target_options = b.standardTargetOptions(.{});
    const release_options = b.standardReleaseOptions();

    var exe = b.addExecutable("mesh_converter", "src/tools/mesh_converter.zig");
    exe.setBuildMode(release_options);
    exe.setTarget(target_options);
    exe.addOptions("build_options", build_options);

    if (tracy) |tracy_path| {
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

    const mesh_pkg = Pkg{
        .name = "mesh",
        .path = .{ .path = "src/libs/mesh.zig" },
    };
    exe.addPackage(mesh_pkg);

    const external = "../3rd_party/zig-gamedev/external/src";
    exe.addIncludeDir(external);

    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("imm32");

    exe.addCSourceFile(external ++ "/cgltf.c", &.{""});

    exe.install();

    return exe;
}
