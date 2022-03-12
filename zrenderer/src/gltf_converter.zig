const std = @import("std");

const s = @import("scene");
const m = s.mesh;
const zm = @import("zmath");

pub const c = @cImport({
    @cInclude("cgltf.h");
    @cInclude("meshoptimizer.h");
    @cInclude("stb_image.h");
});

const assert = std.debug.assert;

pub const STREAM_ELEMENT_SIZE: u32 = @sizeOf(m.VertexData);

fn writeInterleavedVertexAttribute(
    accessor: *c.cgltf_accessor,
    num_vertices: u32,
    vertex_offset: u32,
    accessor_data_buffer: [*]const u8,
    struct_offset: u32,
    mesh_data: *m.MeshData,
) void {
    var vertex_index: u32 = 0;
    while (vertex_index < num_vertices) : (vertex_index += 1) {
        const dest_index = vertex_offset + (vertex_index * STREAM_ELEMENT_SIZE / 4) + struct_offset;
        @memcpy(@ptrCast([*]u8, &mesh_data.vertex_data.items[dest_index]), accessor_data_buffer + (vertex_index * accessor.*.stride), accessor.*.stride);
    }
}

fn extractIndexData(primitive: c.cgltf_primitive, num_indices: u32, mesh_data: *m.MeshData) !void {
    const accessor = primitive.indices;

    assert(accessor.*.buffer_view != null);
    assert(accessor.*.stride == accessor.*.buffer_view.*.stride or accessor.*.buffer_view.*.stride == 0);
    assert((accessor.*.stride * accessor.*.count) == accessor.*.buffer_view.*.size);
    assert(accessor.*.buffer_view.*.buffer.*.data != null);

    const data_addr = @alignCast(4, @ptrCast([*]const u8, accessor.*.buffer_view.*.buffer.*.data) +
        accessor.*.offset + accessor.*.buffer_view.*.offset);

    if (accessor.*.stride == 1) {
        assert(accessor.*.component_type == c.cgltf_component_type_r_8u);
        const src = @ptrCast([*]const u8, data_addr);
        var i: u32 = 0;
        while (i < num_indices) : (i += 1) {
            mesh_data.index_data.appendAssumeCapacity(src[i]);
        }
    } else if (accessor.*.stride == 2) {
        assert(accessor.*.component_type == c.cgltf_component_type_r_16u);
        const src = @ptrCast([*]const u16, data_addr);
        var i: u32 = 0;
        while (i < num_indices) : (i += 1) {
            mesh_data.index_data.appendAssumeCapacity(src[i]);
        }
    } else if (accessor.*.stride == 4) {
        assert(accessor.*.component_type == c.cgltf_component_type_r_32u);
        const src = @ptrCast([*]const u32, data_addr);
        var i: u32 = 0;
        while (i < num_indices) : (i += 1) {
            mesh_data.index_data.appendAssumeCapacity(src[i]);
        }
    } else {
        unreachable;
    }
}

fn extractVertexData(primitive: c.cgltf_primitive, num_vertices: u32, vertex_offset: u32, mesh_data: *m.MeshData) void {
    const num_attribs: u32 = @intCast(u32, primitive.attributes_count);
    var attrib_index: u32 = 0;
    while (attrib_index < num_attribs) : (attrib_index += 1) {
        const attrib = &primitive.attributes[attrib_index];
        const accessor = attrib.data;

        assert(accessor.*.buffer_view != null);
        assert(accessor.*.stride == accessor.*.buffer_view.*.stride or accessor.*.buffer_view.*.stride == 0);
        assert((accessor.*.stride * accessor.*.count) == accessor.*.buffer_view.*.size);
        assert(accessor.*.buffer_view.*.buffer.*.data != null);

        const data_addr = @ptrCast([*]const u8, accessor.*.buffer_view.*.buffer.*.data) +
            accessor.*.offset + accessor.*.buffer_view.*.offset;

        if (attrib.*.type == c.cgltf_attribute_type_position) {
            assert(accessor.*.type == c.cgltf_type_vec3);
            assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
            writeInterleavedVertexAttribute(accessor, num_vertices, vertex_offset, data_addr, @offsetOf(m.VertexData, "position") / 4, mesh_data);
        } else if (attrib.*.type == c.cgltf_attribute_type_normal) {
            assert(accessor.*.type == c.cgltf_type_vec3);
            assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
            writeInterleavedVertexAttribute(accessor, num_vertices, vertex_offset, data_addr, @offsetOf(m.VertexData, "normal") / 4, mesh_data);
        } else if (attrib.*.type == c.cgltf_attribute_type_texcoord) {
            assert(accessor.*.type == c.cgltf_type_vec2);
            assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
            writeInterleavedVertexAttribute(accessor, num_vertices, vertex_offset, data_addr, @offsetOf(m.VertexData, "uv") / 4, mesh_data);
        } else if (attrib.*.type == c.cgltf_attribute_type_tangent) {
            assert(accessor.*.type == c.cgltf_type_vec4);
            assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
            writeInterleavedVertexAttribute(accessor, num_vertices, vertex_offset, data_addr, @offsetOf(m.VertexData, "tangent") / 4, mesh_data);
        } else if (attrib.*.type == c.cgltf_attribute_type_color) {
            assert(accessor.*.type == c.cgltf_type_vec4);
            assert(accessor.*.component_type == c.cgltf_component_type_r_16u);
            var vertex_index: u32 = 0;
            while (vertex_index < num_vertices) : (vertex_index += 1) {
                const dest_index = vertex_offset + (vertex_index * STREAM_ELEMENT_SIZE / 4) + (@offsetOf(m.VertexData, "color") / 4);
                var color: [4]u16 = undefined;
                @memcpy(@ptrCast([*]u8, &color), data_addr + (vertex_index * accessor.*.stride), accessor.*.stride);
                mesh_data.vertex_data.items[dest_index + 0] = @intToFloat(f32, color[0]) / 65535.0;
                mesh_data.vertex_data.items[dest_index + 1] = @intToFloat(f32, color[1]) / 65535.0;
                mesh_data.vertex_data.items[dest_index + 2] = @intToFloat(f32, color[2]) / 65535.0;
                mesh_data.vertex_data.items[dest_index + 3] = @intToFloat(f32, color[3]) / 65535.0;
            }
        }
    }
}

fn convertGLTF(gltf_path: []const u8, mesh_data: *m.MeshData) !void {
    var data: *c.cgltf_data = undefined;
    const options = std.mem.zeroes(c.cgltf_options);
    // Parse.
    {
        const result = c.cgltf_parse_file(&options, gltf_path.ptr, @ptrCast([*c][*c]c.cgltf_data, &data));
        assert(result == c.cgltf_result_success);
    }
    // Load.
    {
        const result = c.cgltf_load_buffers(&options, data, gltf_path.ptr);
        assert(result == c.cgltf_result_success);
    }
    defer c.cgltf_free(data);

    var index_offset: u32 = @intCast(u32, mesh_data.index_data.items.len);
    var vertex_offset: u32 = @intCast(u32, mesh_data.vertex_data.items.len);

    var mesh_index: u32 = 0;
    while (mesh_index < data.meshes_count) : (mesh_index += 1) {
        const gltf_mesh = data.meshes[mesh_index];
        var primitive_index: u32 = 0;
        while (primitive_index < gltf_mesh.primitives_count) : (primitive_index += 1) {
            const primitive = gltf_mesh.primitives[primitive_index];

            var mesh: m.Mesh = undefined;

            mesh.num_streams = 1;
            mesh.stream_element_size[0] = STREAM_ELEMENT_SIZE;
            mesh.stream_offset[0] = vertex_offset * mesh.stream_element_size[0];

            mesh.index_offset = index_offset;
            mesh.vertex_offset = vertex_offset;

            mesh.num_vertices = @intCast(u32, primitive.attributes[0].data.*.count);
            mesh_data.vertex_data.resize(mesh_data.vertex_data.items.len + mesh.num_vertices * mesh.stream_element_size[0]) catch unreachable;
            extractVertexData(primitive, mesh.num_vertices, mesh.vertex_offset, mesh_data);

            // TODO: Add LODs generation with MeshOptimizer
            // NOTE: For now we're only storing LOD 0
            var num_indices = @intCast(u32, primitive.indices.*.count);
            mesh_data.index_data.ensureTotalCapacity(mesh_data.index_data.items.len + num_indices) catch unreachable;
            extractIndexData(primitive, num_indices, mesh_data) catch unreachable;

            mesh.lod_offset[0] = 0;
            mesh.lod_offset[1] = num_indices;
            mesh.num_lods = 1;

            index_offset += num_indices;
            vertex_offset += mesh.num_vertices;

            try mesh_data.meshes.append(mesh);
        }
    }
}

fn extractGLTFPrimitive(primitive: c.cgltf_primitive, mesh_data: *m.MeshData) !void {
    var index_offset: u32 = @intCast(u32, mesh_data.index_data.items.len);
    var vertex_offset: u32 = @intCast(u32, mesh_data.vertex_data.items.len);

    var mesh: m.Mesh = undefined;

    mesh.num_streams = 1;
    mesh.stream_element_size[0] = STREAM_ELEMENT_SIZE;
    mesh.stream_offset[0] = vertex_offset * mesh.stream_element_size[0];

    mesh.index_offset = index_offset;
    mesh.vertex_offset = vertex_offset;

    mesh.num_vertices = @intCast(u32, primitive.attributes[0].data.*.count);
    mesh_data.vertex_data.resize(mesh_data.vertex_data.items.len + mesh.num_vertices * mesh.stream_element_size[0]) catch unreachable;
    extractVertexData(primitive, mesh.num_vertices, mesh.vertex_offset, mesh_data);

    // TODO: Add LODs generation with MeshOptimizer
    // NOTE: For now we're only storing LOD 0
    var num_indices = @intCast(u32, primitive.indices.*.count);
    mesh_data.index_data.ensureTotalCapacity(mesh_data.index_data.items.len + num_indices) catch unreachable;
    extractIndexData(primitive, num_indices, mesh_data) catch unreachable;

    mesh.lod_offset[0] = 0;
    mesh.lod_offset[1] = num_indices;
    mesh.num_lods = 1;

    index_offset += num_indices;
    vertex_offset += mesh.num_vertices;

    try mesh_data.meshes.append(mesh);
}

const NodeExtras = struct {
    static: f32,
};

fn quadToEulerAngles(quat: zm.Quat, x: *f32, y: *f32, z: *f32) void {
    const t0 = 2.0 * (quat[3] * quat[0] + quat[1] * quat[2]);
    const t1 = 1.0 - 2.0 * (quat[0] * quat[0] + quat[1] * quat[1]);
    x.* = std.math.atan2(f32, t0, t1);
    
    var t2 = 2.0 * (quat[3] * quat[1] - quat[2] * quat[0]);
    t2 = if (t2 > 1.0) 1.0 else t2;
    t2 = if (t2 < -1.0) -1.0 else t2;
    y.* = std.math.asin(t2);
    
    const t3 = 2.0 * (quat[3] * quat[2] + quat[0] * quat[1]);
    const t4 = 1.0 - 2.0 * (quat[1] * quat[1] + quat[2] * quat[2]);
    z.* = std.math.atan2(f32, t3, t4);
}

fn convertGLTFScene(gltf_path: []const u8, arena: std.mem.Allocator, scene: *s.Scene, mesh_data: *m.MeshData) !void {
    var data: *c.cgltf_data = undefined;
    const options = std.mem.zeroes(c.cgltf_options);
    // Parse.
    {
        const result = c.cgltf_parse_file(&options, gltf_path.ptr, @ptrCast([*c][*c]c.cgltf_data, &data));
        assert(result == c.cgltf_result_success);
    }
    // Load.
    {
        const result = c.cgltf_load_buffers(&options, data, gltf_path.ptr);
        assert(result == c.cgltf_result_success);
    }
    defer c.cgltf_free(data);
    assert(data.scenes_count == 1);

    const ProcessedMesh = struct {
        mesh_indices: [s.MAX_NUM_MESHES_PER_NODE]u32,
        num_meshes: u32,
    };

    // Create a temporary hash map to map meshes names to already parsed meshes indices
    var mesh_names_hashmap = std.HashMap([]const u8, ProcessedMesh, std.hash_map.StringContext, 80).init(arena);

    var gltf_scene = data.scenes[0];

    var node_index: u32 = 0;
    while (node_index < gltf_scene.nodes_count) : (node_index += 1) {
        var gltf_node = gltf_scene.nodes[node_index];

        std.log.debug("Converting node #{d} of {d} '{s}'", .{ node_index + 1, gltf_scene.nodes_count, gltf_node.*.name });

        // Parse node's camera
        if (gltf_node.*.children_count == 1 and gltf_node.*.children[0].*.camera != null) {
            var child_node = gltf_node.*.children[0];

            var camera: s.Camera = undefined;

            // Extract camera transform
            {
                camera.position[0] = 0.0;
                camera.position[1] = 0.0;
                camera.position[2] = 0.0;

                if (gltf_node.*.has_translation > 0) {
                    camera.position[0] = gltf_node.*.translation[0];
                    camera.position[1] = gltf_node.*.translation[1];
                    camera.position[2] = gltf_node.*.translation[2];
                }

                var orientation = zm.matToQuat(zm.identity());

                if (gltf_node.*.has_rotation > 0) {
                    const parent_orientation = zm.f32x4(gltf_node.*.rotation[0], gltf_node.*.rotation[1], gltf_node.*.rotation[2], gltf_node.*.rotation[3]);
                    orientation = zm.qmul(orientation, parent_orientation);
                }

                if (child_node.*.has_rotation > 0) {
                    const child_orientation = zm.f32x4(child_node.*.rotation[0], child_node.*.rotation[1], child_node.*.rotation[2], child_node.*.rotation[3]);
                    orientation = zm.qmul(orientation, child_orientation);
                }

                var x: f32 = 0.0;
                var y: f32 = 0.0;
                var z: f32 = 0.0;
                quadToEulerAngles(orientation, &x, &y, &z);
                camera.pitch = x;
                camera.yaw = y;
            }

            // Extract camera info
            {
                const gltf_camera = child_node.*.camera;
                assert(gltf_camera.*.type == c.cgltf_camera_type_perspective);

                const perspective_data = gltf_camera.*.data.perspective;

                camera.yfov = perspective_data.yfov;
                camera.znear = perspective_data.znear;
                camera.zfar = 0.0;

                if (perspective_data.has_zfar > 0) {
                    camera.zfar = perspective_data.zfar;
                }
            }

            // Copy camera name for debugging purposes
            var camera_name_slice = std.mem.span(gltf_node.*.name);
            camera.name = std.mem.zeroes([s.MAX_NAME_LENGTH]u8);
            std.mem.copy(u8, &camera.name, camera_name_slice[0..@minimum(camera_name_slice.len, s.MAX_NAME_LENGTH - 1)]);

            // Add camera to scene
            try scene.cameras.append(camera);

            continue;
        }

        if (gltf_node.*.mesh == null) {
            std.log.debug("Skipping node '{s}' because it doesn't contain a mesh", .{gltf_node.*.name});
            continue;
        }

        // Parse node's meshes
        var node: s.Node = undefined;
        node.mobility = .Static;
        var node_name_slice = std.mem.span(gltf_node.*.name);

        // Copy node name for debugging purposes
        node.name = std.mem.zeroes([s.MAX_NAME_LENGTH]u8);
        std.mem.copy(u8, &node.name, node_name_slice[0..@minimum(node_name_slice.len, s.MAX_NAME_LENGTH - 1)]);

        var extra_size: c.cgltf_size = 0;
        var extra_result = c.cgltf_copy_extras_json(data, &gltf_node.*.extras, null, &extra_size);
        if (extra_result == c.cgltf_result_success) {
            var json_string = try arena.alloc(u8, extra_size);
            extra_result = c.cgltf_copy_extras_json(data, &gltf_node.*.extras, @ptrCast([*c]u8, json_string), &extra_size);
            assert(extra_result == c.cgltf_result_success);

            var token_stream = std.json.TokenStream.init(std.mem.sliceAsBytes(std.mem.span(json_string)));
            const extras = try std.json.parse(NodeExtras, &token_stream, .{ .allow_trailing_data = true });

            if (extras.static > 0.5) {
                node.mobility = .Static;
            } else {
                node.mobility = .Moveable;
            }
        }

        // Parse node's meshes
        var gltf_mesh = gltf_node.*.mesh;

        var mesh_name_slice = try std.fmt.allocPrintZ(arena, "{s}", .{gltf_mesh.*.name});
        var mesh_name_bytes = std.mem.sliceAsBytes(mesh_name_slice);

        if (mesh_names_hashmap.get(mesh_name_bytes)) |processed_mesh| {
            node.num_meshes = processed_mesh.num_meshes;
            var i: u32 = 0;
            while (i < s.MAX_NUM_MESHES_PER_NODE) : (i += 1) {
                node.mesh_indices[i] = processed_mesh.mesh_indices[i];
            }
        } else {
            assert(@intCast(u32, gltf_mesh.*.primitives_count) <= s.MAX_NUM_MESHES_PER_NODE);

            var processed_mesh: ProcessedMesh = .{
                .mesh_indices = .{ 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff, 0xffff_ffff },
                .num_meshes = @intCast(u32, gltf_mesh.*.primitives_count),
            };

            var primitive_index: u32 = 0;
            while (primitive_index < gltf_mesh.*.primitives_count) : (primitive_index += 1) {
                processed_mesh.mesh_indices[primitive_index] = @intCast(u32, mesh_data.meshes.items.len);
                try extractGLTFPrimitive(gltf_mesh.*.primitives[primitive_index], mesh_data);
            }

            try mesh_names_hashmap.putNoClobber(mesh_name_bytes, processed_mesh);

            node.num_meshes = processed_mesh.num_meshes;
            var i: u32 = 0;
            while (i < s.MAX_NUM_MESHES_PER_NODE) : (i += 1) {
                node.mesh_indices[i] = processed_mesh.mesh_indices[i];
            }
        }

        // Parse node's transform
        node.transform_index = @intCast(u32, scene.transforms.items.len);

        if (gltf_node.*.has_matrix <= 0 and gltf_node.*.has_translation <= 0 and gltf_node.*.has_rotation <= 0 and gltf_node.*.has_scale <= 0) {
            try scene.transforms.append(zm.identity());
        } else if (gltf_node.*.has_matrix > 0) {
            std.log.debug("TODO: Handle matrix transforms. GLTF 2.0 stores column-major matrices, so we need to transpose them", .{});
            assert(false);
        } else {
            var transform = zm.identity();

            if (gltf_node.*.has_translation > 0) {
                const translation_matrix = zm.translation(gltf_node.*.translation[0], gltf_node.*.translation[1], gltf_node.*.translation[2]);
                transform = zm.mul(transform, translation_matrix);
            }

            if (gltf_node.*.has_rotation > 0) {
                const quat = zm.f32x4(gltf_node.*.rotation[0], gltf_node.*.rotation[1], gltf_node.*.rotation[2], gltf_node.*.rotation[2]);
                const rotation_matrix = zm.matFromQuat(quat);
                transform = zm.mul(transform, rotation_matrix);
            }

            if (gltf_node.*.has_scale > 0) {
                const scaling_matrix = zm.scaling(gltf_node.*.scale[0], gltf_node.*.scale[1], gltf_node.*.scale[2]);
                transform = zm.mul(transform, scaling_matrix);
            }

            try scene.transforms.append(transform);
        }

        // Add node to scene
        try scene.nodes.append(node);
    }
}

const InputType = enum {
    MeshFolder,
    SceneFile,
};

const ParsedArguments = struct {
    input_type: InputType,
    input_path: []u8,
    output_path: []u8,
};

fn parseArgs(mem_allocator: std.mem.Allocator) !ParsedArguments {
    // Extract command line arguments
    var args_iterator = try std.process.argsWithAllocator(mem_allocator);
    defer args_iterator.deinit();

    // Skip the exe path
    _ = args_iterator.skip();

    var result: ParsedArguments = undefined;

    while (args_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg[0..arg.len], "-i")) {
            result.input_type = .MeshFolder;
            if (args_iterator.next()) |input_path| {
                result.input_path = try std.fmt.allocPrintZ(mem_allocator, "{s}", .{input_path[0..input_path.len]});
            } else {
                printUsage();
                std.debug.panic("Failed to find input folder", .{});
            }
        } else if (std.mem.eql(u8, arg[0..arg.len], "-s")) {
            result.input_type = .SceneFile;
            if (args_iterator.next()) |input_path| {
                result.input_path = try std.fmt.allocPrintZ(mem_allocator, "{s}", .{input_path[0..input_path.len]});
            } else {
                printUsage();
                std.debug.panic("Failed to find scene file", .{});
            }
        } else if (std.mem.eql(u8, arg[0..arg.len], "-o")) {
            if (args_iterator.next()) |output_path| {
                result.output_path = try std.fmt.allocPrintZ(mem_allocator, "{s}", .{output_path[0..output_path.len]});
            } else {
                printUsage();
                std.debug.panic("Failed to output path", .{});
            }
        } else {
            printUsage();
            std.debug.panic("Bad arguments", .{});
        }
    }

    return result;
}

fn printUsage() void {
    std.log.info("Usage:", .{});
    std.log.info("\tgltf_converter.exe -i path/to/gltf_files/ -o path/to/output/folder/\n", .{});
    std.log.info("\tgltf_converter.exe -s path/to/scene.gltf -o path/to/output/folder/\n", .{});
}

pub fn main() !void {
    // Create main memory allocator for our application.
    var gpa_allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa_allocator_state.deinit();
        assert(leaked == false);
    }
    const gpa_allocator = gpa_allocator_state.allocator();

    var arena_allocator_state = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena_allocator_state.deinit();
    const arena_allocator = arena_allocator_state.allocator();

    const parsed_arguments = try parseArgs(gpa_allocator);
    defer gpa_allocator.free(parsed_arguments.input_path);
    defer gpa_allocator.free(parsed_arguments.output_path);

    std.log.info("Input type: '{s}'", .{parsed_arguments.input_type});
    std.log.info("Input path: '{s}'", .{parsed_arguments.input_path});
    std.log.info("Output path: '{s}'", .{parsed_arguments.output_path});

    if (parsed_arguments.input_type == .MeshFolder) {
        var mesh_data: m.MeshData = .{
            .index_data = std.ArrayList(u32).init(gpa_allocator),
            .vertex_data = std.ArrayList(f32).init(gpa_allocator),
            .meshes = std.ArrayList(m.Mesh).init(gpa_allocator),
        };
        defer mesh_data.unload(gpa_allocator);

        var dir = try std.fs.cwd().openDir(parsed_arguments.input_path, .{ .iterate = true });
        defer dir.close();
        var dir_it = dir.iterate();

        while (try dir_it.next()) |file| {
            if (file.kind == .File) {
                if (std.mem.eql(u8, "gltf", file.name[file.name.len - 4 .. file.name.len])) {
                    var file_path = try std.fmt.allocPrintZ(gpa_allocator, "{s}/{s}", .{ parsed_arguments.input_path, file.name });
                    defer gpa_allocator.free(file_path);

                    try convertGLTF(file_path, &mesh_data);
                }
            }
        }

        var output_file_path = try std.fmt.allocPrintZ(gpa_allocator, "{s}/meshes.bin", .{parsed_arguments.output_path});
        defer gpa_allocator.free(output_file_path);
        var output_file = try std.fs.cwd().createFile(output_file_path, .{ .read = true });
        defer output_file.close();
        try mesh_data.serialize(output_file);
    } else {
        std.log.debug("Converting scene {s}...", .{parsed_arguments.input_path});

        var mesh_data: m.MeshData = .{
            .index_data = std.ArrayList(u32).init(gpa_allocator),
            .vertex_data = std.ArrayList(f32).init(gpa_allocator),
            .meshes = std.ArrayList(m.Mesh).init(gpa_allocator),
        };
        defer mesh_data.index_data.deinit();
        defer mesh_data.vertex_data.deinit();
        defer mesh_data.meshes.deinit();

        var scene: s.Scene = .{
            .nodes = std.ArrayList(s.Node).init(gpa_allocator),
            .transforms = std.ArrayList(zm.Mat).init(gpa_allocator),
            .cameras = std.ArrayList(s.Camera).init(gpa_allocator),
            .active_camera_index = 0,
        };
        defer scene.unload(gpa_allocator);

        try convertGLTFScene(parsed_arguments.input_path, arena_allocator, &scene, &mesh_data);

        var output_meshes_file_path = try std.fmt.allocPrintZ(gpa_allocator, "{s}/meshes.bin", .{parsed_arguments.output_path});
        defer gpa_allocator.free(output_meshes_file_path);
        var meshes_file = try std.fs.cwd().createFile(output_meshes_file_path, .{ .read = true });
        defer meshes_file.close();
        try mesh_data.serialize(meshes_file);

        var output_scene_file_path = try std.fmt.allocPrintZ(gpa_allocator, "{s}/scene.bin", .{parsed_arguments.output_path});
        defer gpa_allocator.free(output_scene_file_path);
        var scene_file = try std.fs.cwd().createFile(output_scene_file_path, .{ .read = true });
        defer scene_file.close();
        try scene.serialize(scene_file);
    }
}
