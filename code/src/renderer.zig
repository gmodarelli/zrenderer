const std = @import("std");
const win32 = @import("win32");
const w = win32.base;
const d2d1 = win32.d2d1;
const d3d = win32.d3d;
const d3d12 = win32.d3d12;
const dwrite = win32.dwrite;
const common = @import("common");
const gr = common.graphics;
const lib = common.library;
const c = common.c;
const pix = common.pix;
const vm = common.vectormath;
const math = std.math;
const assert = std.debug.assert;
const hrPanic = lib.hrPanic;
const hrPanicOnFail = lib.hrPanicOnFail;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const Vec2 = vm.Vec2;
const Vec3 = vm.Vec3;
const Vec4 = vm.Vec4;
const Mat4 = vm.Mat4;

pub export var D3D12SDKVersion: u32 = 4;
pub export var D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

const PBRMaterial = struct {
    base_color: Vec3,
    roughness: f32,
    metallic: f32,
    base_color_tex_index: u32,
    metallic_roughness_tex_index: u32,
    normal_tex_index: u32,
};

const PersistentResourceHandle = struct {
    resource: gr.ResourceHandle,
    persistent_descriptor: gr.PersistentDescriptor,
};

const ResourceView = struct {
    resource: gr.ResourceHandle,
    view: d3d12.CPU_DESCRIPTOR_HANDLE,
};

const Vertex = struct {
    position: Vec3,
    normal: Vec3,
    texcoords0: Vec2,
    tangent: Vec4,
};

const Mesh = struct {
    index_offset: u32,
    vertex_offset: u32,
    num_indices: u32,
    num_vertices: u32,
    material_index: u32,
};

pub const Scene = struct {
    vertices: std.ArrayList(Vertex),
    indices: std.ArrayList(u32),
    meshes: std.ArrayList(Mesh),
    materials: std.ArrayList(PBRMaterial),
    textures: std.ArrayList(PersistentResourceHandle),

    pub fn loadFromGltf(arena: std.mem.Allocator, file_path: []const u8, grfx: *gr.GraphicsContext) Scene {
        var all_meshes = std.ArrayList(Mesh).init(arena);
        var all_vertices = std.ArrayList(Vertex).init(arena);
        var all_indices = std.ArrayList(u32).init(arena);
        var all_materials = std.ArrayList(PBRMaterial).init(arena);
        var all_textures = std.ArrayList(PersistentResourceHandle).init(arena);

        var indices = std.ArrayList(u32).init(arena);
        var positions = std.ArrayList(Vec3).init(arena);
        var normals = std.ArrayList(Vec3).init(arena);
        var texcoords0 = std.ArrayList(Vec2).init(arena);
        var tangents = std.ArrayList(Vec4).init(arena);
        defer indices.deinit();
        defer positions.deinit();
        defer normals.deinit();
        defer texcoords0.deinit();
        defer tangents.deinit();

        const data = lib.parseAndLoadGltfFile(file_path);
        defer c.cgltf_free(data);

        const num_meshes = @intCast(u32, data.meshes_count);
        var mesh_index: u32 = 0;

        while (mesh_index < num_meshes) : (mesh_index += 1) {
            const num_prims = @intCast(u32, data.meshes[mesh_index].primitives_count);
            var prim_index: u32 = 0;

            while (prim_index < num_prims) : (prim_index += 1) {
                const pre_indices_len = indices.items.len;
                const pre_positions_len = positions.items.len;

                lib.appendMeshPrimitive(data, mesh_index, prim_index, &indices, &positions, &normals, &texcoords0, &tangents);

                const num_materials = @intCast(u32, data.materials_count);
                var material_index: u32 = 0;
                var assigned_material_index: u32 = 0xffff_ffff;

                while (material_index < num_materials) : (material_index += 1) {
                    const prim = &data.meshes[mesh_index].primitives[prim_index];
                    if (prim.material == &data.materials[material_index]) {
                        assigned_material_index = material_index;
                        break;
                    }
                }
                assert(assigned_material_index != 0xffff_ffff);

                all_meshes.append(.{
                    .index_offset = @intCast(u32, pre_indices_len),
                    .vertex_offset = @intCast(u32, pre_positions_len),
                    .num_indices = @intCast(u32, indices.items.len - pre_indices_len),
                    .num_vertices = @intCast(u32, positions.items.len - pre_positions_len),
                    .material_index = assigned_material_index,
                }) catch unreachable;
            }
        }

        all_indices.ensureTotalCapacity(indices.items.len) catch unreachable;
        for (indices.items) |index| {
            all_indices.appendAssumeCapacity(index);
        }

        all_vertices.ensureTotalCapacity(positions.items.len) catch unreachable;
        for (positions.items) |_, index| {
            all_vertices.appendAssumeCapacity(.{
                .position = positions.items[index],
                .normal = normals.items[index],
                .texcoords0 = texcoords0.items[index],
                .tangent = tangents.items[index],
            });
        }

        const num_materials = @intCast(u32, data.materials_count);
        var material_index: u32 = 0;
        all_materials.ensureTotalCapacity(num_materials) catch unreachable;

        while (material_index < num_materials) : (material_index += 1) {
            const gltf_material = &data.materials[material_index];
            assert(gltf_material.has_pbr_metallic_roughness == 1);

            const mr = &gltf_material.pbr_metallic_roughness;

            const num_images = @intCast(u32, data.images_count);
            const invalid_image_index = num_images;

            var base_color_tex_index: u32 = invalid_image_index;
            var metallic_roughness_tex_index: u32 = invalid_image_index;
            var normal_tex_index: u32 = invalid_image_index;

            var image_index: u32 = 0;

            while (image_index < num_images) : (image_index += 1) {
                const image = &data.images[image_index];
                assert(image.uri != null);

                if (mr.base_color_texture.texture != null and
                    mr.base_color_texture.texture.*.image.*.uri == image.uri)
                {
                    assert(base_color_tex_index == invalid_image_index);
                    base_color_tex_index = image_index;
                }

                if (mr.metallic_roughness_texture.texture != null and
                    mr.metallic_roughness_texture.texture.*.image.*.uri == image.uri)
                {
                    assert(metallic_roughness_tex_index == invalid_image_index);
                    metallic_roughness_tex_index = image_index;
                }

                if (gltf_material.normal_texture.texture != null and
                    gltf_material.normal_texture.texture.*.image.*.uri == image.uri)
                {
                    assert(normal_tex_index == invalid_image_index);
                    normal_tex_index = image_index;
                }
            }
            assert(base_color_tex_index != invalid_image_index);

            all_materials.appendAssumeCapacity(.{
                .base_color = Vec3.init(mr.base_color_factor[0], mr.base_color_factor[1], mr.base_color_factor[2]),
                .roughness = mr.roughness_factor,
                .metallic = mr.metallic_factor,
                .base_color_tex_index = base_color_tex_index,
                .metallic_roughness_tex_index = metallic_roughness_tex_index,
                .normal_tex_index = normal_tex_index,
            });
        }

        const num_images = @intCast(u32, data.images_count);
        var image_index: u32 = 0;
        all_textures.ensureTotalCapacity(num_images + 1) catch unreachable;

        while (image_index < num_images) : (image_index += 1) {
            const image = &data.images[image_index];

            var buffer: [128]u8 = undefined;
            const path = std.fmt.bufPrint(buffer[0..], "content/textuers/{s}", .{image.uri}) catch unreachable;

            const resource = grfx.createAndUploadTex2dFromFile(path, .{}) catch unreachable;
            const persistent_descriptor = grfx.allocatePersistentGpuDescriptors(1);
            grfx.device.CreateShaderResourceView(grfx.getResource(resource), null, persistent_descriptor.cpu_handle);

            all_textures.appendAssumeCapacity(.{ .resource = resource, .persistent_descriptor = persistent_descriptor });
        }

        // NOTE(gmodarelli): We're replacing the indices that index into the textures array list, with their
        // respective GPU descriptor indices
        var i: u32 = 0;
        while (i < all_materials.items.len) : (i += 1) {
            var tex_index = all_materials.items[i].base_color_tex_index;
            if (tex_index >= 0 and tex_index < all_textures.items.len) {
                all_materials.items[i].base_color_tex_index = all_textures.items[tex_index].persistent_descriptor.index;
            }

            tex_index = all_materials.items[i].metallic_roughness_tex_index;
            if (tex_index >= 0 and tex_index < all_textures.items.len) {
                all_materials.items[i].metallic_roughness_tex_index = all_textures.items[tex_index].persistent_descriptor.index;
            }

            tex_index = all_materials.items[i].normal_tex_index;
            if (tex_index >= 0 and tex_index < all_textures.items.len) {
                all_materials.items[i].normal_tex_index = all_textures.items[tex_index].persistent_descriptor.index;
            }
        }

        return .{
            .vertices = all_vertices,
            .indices = all_indices,
            .meshes = all_meshes,
            .materials = all_materials,
            .textures = all_textures,
        };
    }

    pub fn deinit(s: *Scene, grfx: *gr.GraphicsContext) void {
        for (s.textures.items) |texture| {
            _ = grfx.releaseResource(texture.resource);
        }

        s.meshes.deinit();
        s.vertices.deinit();
        s.indices.deinit();
        s.materials.deinit();
        s.textures.deinit();
    }
};

pub const Renderer = struct {
    grfx: gr.GraphicsContext,
    gui: gr.GuiContext,
    frame_stats: lib.FrameStats,

    depth_texture: ResourceView,

    brush: *d2d1.ISolidColorBrush,
    info_tfmt: *dwrite.ITextFormat,
    title_tfmt: *dwrite.ITextFormat,

    current_scene: Scene,

    vertex_buffer: gr.ResourceHandle,
    index_buffer: gr.ResourceHandle,
    material_buffer: PersistentResourceHandle,

    pub fn init(gpa_allocator: std.mem.Allocator, window: w.HWND) Renderer {
        var grfx = gr.GraphicsContext.init(window);

        // V-Sync
        grfx.present_flags = 0;
        grfx.present_interval = 1;

        var arena_allocator_state = std.heap.ArenaAllocator.init(gpa_allocator);
        defer arena_allocator_state.deinit();
        const arena_allocator = arena_allocator_state.allocator();

        const brush = blk: {
            var maybe_brush: ?*d2d1.ISolidColorBrush = null;
            hrPanicOnFail(grfx.d2d.context.CreateSolidColorBrush(
                &.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 0.5 },
                null,
                &maybe_brush,
            ));
            break :blk maybe_brush.?;
        };

        const info_tfmt = blk: {
            var info_tfmt: *dwrite.ITextFormat = undefined;
            hrPanicOnFail(grfx.dwrite_factory.CreateTextFormat(
                L("Verdana"),
                null,
                dwrite.FONT_WEIGHT.NORMAL,
                dwrite.FONT_STYLE.NORMAL,
                dwrite.FONT_STRETCH.NORMAL,
                32.0,
                L("en-us"),
                @ptrCast(*?*dwrite.ITextFormat, &info_tfmt),
            ));
            break :blk info_tfmt;
        };
        hrPanicOnFail(info_tfmt.SetTextAlignment(.LEADING));
        hrPanicOnFail(info_tfmt.SetParagraphAlignment(.NEAR));

        const title_tfmt = blk: {
            var title_tfmt: *dwrite.ITextFormat = undefined;
            hrPanicOnFail(grfx.dwrite_factory.CreateTextFormat(
                L("Verdana"),
                null,
                dwrite.FONT_WEIGHT.NORMAL,
                dwrite.FONT_STYLE.NORMAL,
                dwrite.FONT_STRETCH.NORMAL,
                72.0,
                L("en-us"),
                @ptrCast(*?*dwrite.ITextFormat, &title_tfmt),
            ));
            break :blk title_tfmt;
        };
        hrPanicOnFail(title_tfmt.SetTextAlignment(.CENTER));
        hrPanicOnFail(title_tfmt.SetParagraphAlignment(.CENTER));

        const depth_texture = .{
            .resource = grfx.createCommittedResource(
                .DEFAULT,
                d3d12.HEAP_FLAG_NONE,
                &blk: {
                    var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, grfx.viewport_width, grfx.viewport_height, 1);
                    desc.Flags = d3d12.RESOURCE_FLAG_ALLOW_DEPTH_STENCIL | d3d12.RESOURCE_FLAG_DENY_SHADER_RESOURCE;
                    break :blk desc;
                },
                d3d12.RESOURCE_STATE_DEPTH_WRITE,
                &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
            ) catch |err| hrPanic(err),
            .view = grfx.allocateCpuDescriptors(.DSV, 1),
        };
        grfx.device.CreateDepthStencilView(grfx.getResource(depth_texture.resource), null, depth_texture.view);

        grfx.beginFrame();

        var gui = gr.GuiContext.init(arena_allocator, &grfx, 1);

        grfx.flushResourceBarriers();

        grfx.endFrame();
        w.kernel32.Sleep(100);
        grfx.finishGpuCommands();

        return .{
            .grfx = grfx,
            .gui = gui,
            .frame_stats = lib.FrameStats.init(),
            .depth_texture = depth_texture,
            .brush = brush,
            .info_tfmt = info_tfmt,
            .title_tfmt = title_tfmt,
            .vertex_buffer = undefined,
            .index_buffer = undefined,
            .material_buffer = undefined,
            .current_scene = undefined,
        };
    }

    pub fn loadScene(r: *Renderer, arena: std.mem.Allocator, file_path: []const u8) void {
        r.grfx.finishGpuCommands();
        r.grfx.beginFrame();

        r.current_scene = Scene.loadFromGltf(arena, file_path, &r.grfx);

        const vertex_buffer = blk: {
            var vertex_buffer = r.grfx.createCommittedResource(
                .DEFAULT,
                d3d12.HEAP_FLAG_NONE,
                &d3d12.RESOURCE_DESC.initBuffer(r.current_scene.vertices.items.len * @sizeOf(Vertex)),
                d3d12.RESOURCE_STATE_COPY_DEST,
                null,
            ) catch |err| hrPanic(err);
            const upload = r.grfx.allocateUploadBufferRegion(Vertex, @intCast(u32, r.current_scene.vertices.items.len));
            for (r.current_scene.vertices.items) |vertex, i| {
                upload.cpu_slice[i] = vertex;
            }
            r.grfx.cmdlist.CopyBufferRegion(
                r.grfx.getResource(vertex_buffer),
                0,
                upload.buffer,
                upload.buffer_offset,
                upload.cpu_slice.len * @sizeOf(@TypeOf(upload.cpu_slice[0])),
            );
            r.grfx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);
            break :blk vertex_buffer;
        };

        const index_buffer = blk: {
            var index_buffer = r.grfx.createCommittedResource(
                .DEFAULT,
                d3d12.HEAP_FLAG_NONE,
                &d3d12.RESOURCE_DESC.initBuffer(r.current_scene.indices.items.len * @sizeOf(u32)),
                d3d12.RESOURCE_STATE_COPY_DEST,
                null,
            ) catch |err| hrPanic(err);
            const upload = r.grfx.allocateUploadBufferRegion(u32, @intCast(u32, r.current_scene.indices.items.len));
            for (r.current_scene.indices.items) |index, i| {
                upload.cpu_slice[i] = index;
            }
            r.grfx.cmdlist.CopyBufferRegion(
                r.grfx.getResource(index_buffer),
                0,
                upload.buffer,
                upload.buffer_offset,
                upload.cpu_slice.len * @sizeOf(@TypeOf(upload.cpu_slice[0])),
            );
            r.grfx.addTransitionBarrier(index_buffer, d3d12.RESOURCE_STATE_INDEX_BUFFER);
            break :blk index_buffer;
        };

        const material_buffer = blk: {
            var material_buffer = r.grfx.createCommittedResource(
                .DEFAULT,
                d3d12.HEAP_FLAG_NONE,
                &d3d12.RESOURCE_DESC.initBuffer(r.current_scene.materials.items.len * @sizeOf(PBRMaterial)),
                d3d12.RESOURCE_STATE_COPY_DEST,
                null,
            ) catch |err| hrPanic(err);
            const upload = r.grfx.allocateUploadBufferRegion(PBRMaterial, @intCast(u32, r.current_scene.materials.items.len));
            for (r.current_scene.materials.items) |material, i| {
                upload.cpu_slice[i] = material;
            }
            r.grfx.cmdlist.CopyBufferRegion(
                r.grfx.getResource(material_buffer),
                0,
                upload.buffer,
                upload.buffer_offset,
                upload.cpu_slice.len * @sizeOf(@TypeOf(upload.cpu_slice[0])),
            );
            // r.grfx.addTransitionBarrier(vertex_buffer, d3d12.RESOURCE_STATE_);

            const persistent_descriptor = r.grfx.allocatePersistentGpuDescriptors(1);
            const srv_desc = d3d12.SHADER_RESOURCE_VIEW_DESC.initStructuredBuffer(0, @intCast(u32, r.current_scene.materials.items.len), @sizeOf(PBRMaterial));
            r.grfx.device.CreateShaderResourceView(r.grfx.getResource(material_buffer), &srv_desc, persistent_descriptor.cpu_handle);

            break :blk .{
                .resource = material_buffer,
                .persistent_descriptor = persistent_descriptor,
            };
        };

        r.vertex_buffer = vertex_buffer;
        r.index_buffer = index_buffer;
        r.material_buffer = material_buffer;

        r.grfx.endFrame();
    }

    pub fn deinit(r: *Renderer) void {
        r.grfx.finishGpuCommands();
        r.current_scene.deinit(&r.grfx);

        _ = r.grfx.releaseResource(r.depth_texture.resource);
        _ = r.grfx.releaseResource(r.vertex_buffer);
        _ = r.grfx.releaseResource(r.index_buffer);
        _ = r.grfx.releaseResource(r.material_buffer.resource);

        _ = r.brush.Release();
        _ = r.info_tfmt.Release();
        _ = r.title_tfmt.Release();
        r.gui.deinit(&r.grfx);
        r.grfx.deinit();
        r.* = undefined;
    }

    pub fn render(r: *Renderer) void {
        var grfx = &r.grfx;
        grfx.beginFrame();

        const back_buffer = grfx.getBackBuffer();
        grfx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
        grfx.flushResourceBarriers();

        grfx.cmdlist.OMSetRenderTargets(
            1,
            &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
            w.TRUE,
            &r.depth_texture.view,
        );
        grfx.cmdlist.ClearRenderTargetView(
            back_buffer.descriptor_handle,
            &[4]f32{ 0.0, 0.0, 0.0, 0.0 },
            0,
            null,
        );
        grfx.cmdlist.ClearDepthStencilView(r.depth_texture.view, d3d12.CLEAR_FLAG_DEPTH, 1.0, 0, 0, null);

        // r.gui.draw(grfx);

        grfx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_PRESENT);
        grfx.flushResourceBarriers();
        grfx.endFrame();
    }
};