// This intro application shows how to create window, setup DirectX 12 context, clear the window
// and draw text using Direct2D.

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const zwin32 = @import("zwin32");
const w = zwin32.base;
const d3d12 = zwin32.d3d12;
const dwrite = zwin32.dwrite;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");
const common = @import("common");
const GuiRenderer = common.GuiRenderer;
const c = common.c;
const zm = @import("zmath");

const s = @import("scene");
const VertexData = s.mesh.VertexData;

// We need to export below symbols for DirectX 12 Agility SDK.
pub export var D3D12SDKVersion: u32 = 4;
pub export var D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const content_dir = @import("build_options").content_dir;

const window_name = "zrenderer";
const window_width = 1920;
const window_height = 1080;

// By convention, we use 'Pso_' prefix for structures that are also defined in HLSL code
const Pso_FrameConst = struct {
    matrix_vp: [16]f32,
};

const Pso_DrawConst = struct {
    object_to_world: [16]f32,
};

const DemoState = struct {
    gctx: zd3d12.GraphicsContext,
    guictx: GuiRenderer,
    frame_stats: common.FrameStats,

    scene: s.Scene,
    mesh_data: s.mesh.MeshData,

    uber_pso: zd3d12.PipelineHandle,

    vertex_buffer: zd3d12.ResourceHandle,
    index_buffer: zd3d12.ResourceHandle,

    depth_texture: zd3d12.ResourceHandle,
    depth_texture_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,
};

fn init(allocator: std.mem.Allocator) !DemoState {
    // Create application window and initialize dear imgui library.
    const window = common.initWindow(allocator, window_name, window_width, window_height) catch unreachable;

    // Create temporary memory allocator for use during initialization. We pass this allocator to all
    // subsystems that need memory and then free everyting with a single deallocation.
    var arena_allocator_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator_state.deinit();
    const arena_allocator = arena_allocator_state.allocator();

    // Create DirectX 12 context.
    var gctx = zd3d12.GraphicsContext.init(allocator, window);

    const uber_pso = blk: {
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("TEXCOORD", 0, .R32G32_FLOAT, 0, 12, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("COLOR", 0, .R32G32B32_FLOAT, 0, 20, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("NORMAL", 0, .R32G32B32_FLOAT, 0, 32, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("TANGENT", 0, .R32G32B32A32_FLOAT, 0, 44, .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.RasterizerState.FrontCounterClockwise = w.TRUE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena_allocator,
            &pso_desc,
            "content/shaders/uber.vs.cso",
            "content/shaders/uber.ps.cso",
        );
    };

    // Create the depth texture resource.
    const depth_texture = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, gctx.viewport_width, gctx.viewport_height, 1);
            desc.Flags = d3d12.RESOURCE_FLAG_ALLOW_DEPTH_STENCIL | d3d12.RESOURCE_FLAG_DENY_SHADER_RESOURCE;
            break :blk desc;
        },
        d3d12.RESOURCE_STATE_DEPTH_WRITE,
        &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
    ) catch |err| hrPanic(err);

    // Create a depth texture 'view'
    const depth_texture_dsv = gctx.allocateCpuDescriptors(.DSV, 1);
    gctx.device.CreateDepthStencilView(
        gctx.lookupResource(depth_texture).?,
        null,
        depth_texture_dsv,
    );

    var scene_file = try std.fs.cwd().openFile("content/scenes/test_scene/scene.bin", .{});
    defer scene_file.close();

    var mesh_data_file = try std.fs.cwd().openFile("content/scenes/test_scene/meshes.bin", .{});
    defer mesh_data_file.close();

    var scene = try s.Scene.load(scene_file, allocator);
    var mesh_data = try s.mesh.MeshData.load(mesh_data_file, allocator);

    // Create vertex buffer and return a *handle* to the underlying Direct3D12 resource.
    const vertex_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(@intCast(u32, mesh_data.vertex_data.items.len * @sizeOf(f32))),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    // Create index buffer and return a *handle* to the underlying Direct3D12 resource.
    const index_buffer = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &d3d12.RESOURCE_DESC.initBuffer(@intCast(u32, mesh_data.index_data.items.len * @sizeOf(u32))),
        d3d12.RESOURCE_STATE_COPY_DEST,
        null,
    ) catch |err| hrPanic(err);

    // Enable vsync.
    gctx.present_flags = 0;
    gctx.present_interval = 1;

    // Open D3D12 command list, setup descriptor heap, etc. After this call we can upload resources to the GPU,
    // draw 3D graphics etc.
    gctx.beginFrame();

    // Create and upload graphics resources for dear imgui renderer.
    var guictx = GuiRenderer.init(arena_allocator, &gctx, 1, content_dir);

    // Fill vertex buffer with vertex data.
    {
        // Allocate memory from upload heap and fill it with vertex data.
        const verts = gctx.allocateUploadBufferRegion(f32, @intCast(u32, mesh_data.vertex_data.items.len));
        // TODO: Copy in one operation, instead of iterating over all the floats
        for (mesh_data.vertex_data.items) |_, i| {
            verts.cpu_slice[i] = mesh_data.vertex_data.items[i];
        }

        // Copy vertex data from upload heap to vertex buffer resource that resides in high-performance memory
        // on the GPU.
        gctx.cmdlist.CopyBufferRegion(
            gctx.lookupResource(vertex_buffer).?,
            0,
            verts.buffer,
            verts.buffer_offset,
            verts.cpu_slice.len * @sizeOf(@TypeOf(verts.cpu_slice[0])),
        );
    }

    // Fill index buffer with index data.
    {
        // Allocate memory from upload heap and fill it with index data.
        const indices = gctx.allocateUploadBufferRegion(u32, @intCast(u32, mesh_data.index_data.items.len));
        // TODO: Copy in one operation, instead of iterating over all the indices
        for (mesh_data.index_data.items) |_, i| {
            indices.cpu_slice[i] = mesh_data.index_data.items[i];
        }

        // Copy index data from upload heap to index buffer resource that resides in high-performance memory
        // on the GPU.
        gctx.cmdlist.CopyBufferRegion(
            gctx.lookupResource(index_buffer).?,
            0,
            indices.buffer,
            indices.buffer_offset,
            indices.cpu_slice.len * @sizeOf(@TypeOf(indices.cpu_slice[0])),
        );
    }

    // Transition vertex and index buffers from 'copy dest' state to the state appropriate for rendering.
    gctx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
    gctx.addTransitionBarrier(index_buffer, d3d12.RESOURCE_STATE_INDEX_BUFFER);
    gctx.flushResourceBarriers();

    // This will send command list to the GPU, call 'Present' and do some other bookkeeping.
    gctx.endFrame();

    // Wait for the GPU to finish all commands.
    gctx.finishGpuCommands();

    return DemoState{
        .gctx = gctx,
        .guictx = guictx,
        .frame_stats = common.FrameStats.init(),

        .uber_pso = uber_pso,
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,

        .scene = scene,
        .mesh_data = mesh_data,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}

fn deinit(demo: *DemoState, allocator: std.mem.Allocator) void {
    demo.gctx.finishGpuCommands();
    demo.guictx.deinit(&demo.gctx);
    demo.gctx.deinit(allocator);
    demo.scene.unload(allocator);
    demo.mesh_data.unload(allocator);
    common.deinitWindow(allocator);
    demo.* = undefined;
}

fn update(demo: *DemoState) void {
    // Update frame counter and fps stats.
    demo.frame_stats.update(demo.gctx.window, window_name);
    const dt = demo.frame_stats.delta_time;

    // Update dear imgui common. After this call we can define our widgets.
    common.newImGuiFrame(dt);

    _ = c.igBegin("Scene Outliner", null, c.ImGuiWindowFlags_NoSavedSettings);
    var node_index: u32 = 0;
    while (node_index < demo.scene.nodes.items.len) : (node_index += 1) {
        c.igBulletText("", "");
        c.igSameLine(0, -1);
        c.igTextColored(.{ .x = 0, .y = 0.8, .z = 0, .w = 1 }, @ptrCast([*c]const u8, &demo.scene.nodes.items[node_index].name), "");
    }

    c.igEnd();
}

fn draw(demo: *DemoState) void {
    var gctx = &demo.gctx;

    var active_camera = demo.scene.cameras.items[demo.scene.active_camera_index];
    const view_matrix = zm.lookAtRh(
        zm.load(active_camera.position[0..], zm.Vec, 3),
        zm.load(active_camera.forward[0..], zm.Vec, 3),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const proj_matrix = zm.perspectiveFovRh(
        active_camera.yfov,
        @intToFloat(f32, gctx.viewport_width) / @intToFloat(f32, gctx.viewport_height),
        active_camera.znear,
        active_camera.zfar,
    );
    const vp_matrix = zm.mul(view_matrix, proj_matrix);

    // Begin DirectX 12 rendering.
    gctx.beginFrame();

    // Get current back buffer resource and transition it to 'render target' state.
    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w.TRUE,
        &demo.depth_texture_dsv,
    );
    gctx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &[4]f32{ 0.0, 0.0, 0.0, 1.0 },
        0,
        null,
    );
    gctx.cmdlist.ClearDepthStencilView(demo.depth_texture_dsv, d3d12.CLEAR_FLAG_DEPTH, 1.0, 0, 0, null);

    // Set graphics state and draw
    gctx.setCurrentPipeline(demo.uber_pso);
    gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);

    gctx.cmdlist.IASetVertexBuffers(0, 1, &[_]d3d12.VERTEX_BUFFER_VIEW{.{
        .BufferLocation = gctx.lookupResource(demo.vertex_buffer).?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(u32, demo.mesh_data.vertex_data.items.len * @sizeOf(f32)),
        .StrideInBytes = @sizeOf(VertexData),
    }});
    gctx.cmdlist.IASetIndexBuffer(&.{
        .BufferLocation = gctx.lookupResource(demo.index_buffer).?.GetGPUVirtualAddress(),
        .SizeInBytes = @intCast(u32, demo.mesh_data.index_data.items.len * @sizeOf(u32)),
        .Format = .R32_UINT,
    });

    // Upload per-framce constant data (camera transform)
    {
        // Allocate memory for one instance of Pso_FrameConst structure.
        const mem = gctx.allocateUploadMemory(Pso_FrameConst, 1);

        // Copy 'vp_matrix' matrix to upload memory. We need to transpose it because
        // HLSL uses column-major matrices by default (zmath uses row-major matrices).
        zm.storeMat(mem.cpu_slice[0].matrix_vp[0..], zm.transpose(vp_matrix));

        // Set GPU handle of our allocated memory region so that it is visible to the shader.
        gctx.cmdlist.SetGraphicsRootConstantBufferView(
            0, // Slot index 0 in Root Signature (CBV(b1)).
            mem.gpu_base,
        );
    }

    // For each node, upload per-draw constant data (object ot world transform) and draw.
    var node_index: u32 = 0;
    while (node_index < demo.scene.nodes.items.len) : (node_index += 1) {
        const node = demo.scene.nodes.items[node_index];

        // Allocate memory for one instance of Pso_DrawConst structure.
        const mem = gctx.allocateUploadMemory(Pso_DrawConst, 1);

        // Copy 'object_to_world' matrix to upload memory. We need to transpose it because
        // HLSL uses column-major matrices by default (zmath uses row-major matrices).
        zm.storeMat(mem.cpu_slice[0].object_to_world[0..], zm.transpose(demo.scene.transforms.items[node.transform_index]));

        // Set GPU handle of our allocated memory region so that it is visible to the shader.
        gctx.cmdlist.SetGraphicsRootConstantBufferView(
            1, // Slot index 1 in Root Signature (CBV(b1)).
            mem.gpu_base,
        );

        var mesh_index: u32 = 0;
        while (mesh_index < node.num_meshes) : (mesh_index += 1) {
            var mesh = demo.mesh_data.meshes.items[node.mesh_indices[mesh_index]];
            const num_indices = @intCast(u32, mesh.lodSize(0));
            // gctx.cmdlist.DrawIndexedInstanced(num_indices, 1, mesh.index_offset + mesh.lod_offset[0], @intCast(i32, mesh.vertex_offset), 0);
            gctx.cmdlist.DrawIndexedInstanced(num_indices, 1, 0, 0, 0);
        }
    }

    // Draw dear imgui (not used in this demo).
    demo.guictx.draw(gctx);

    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_PRESENT);
    gctx.flushResourceBarriers();

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
}

pub fn main() !void {
    // Initialize some low-level Windows stuff (DPI awarness, COM), check Windows version and also check
    // if DirectX 12 Agility SDK is supported.
    common.init();
    defer common.deinit();

    // Create main memory allocator for our application.
    var gpa_allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator_state.deinit();
        std.debug.assert(leaked == false);
    }
    const gpa_allocator = gpa_allocator_state.allocator();

    var demo = try init(gpa_allocator);
    defer deinit(&demo, gpa_allocator);

    while (true) {
        var message = std.mem.zeroes(w.user32.MSG);
        const has_message = w.user32.peekMessageA(&message, null, 0, 0, w.user32.PM_REMOVE) catch false;
        if (has_message) {
            _ = w.user32.translateMessage(&message);
            _ = w.user32.dispatchMessageA(&message);
            if (message.message == w.user32.WM_QUIT) {
                break;
            }
        } else {
            update(&demo);
            draw(&demo);
        }
    }
}
