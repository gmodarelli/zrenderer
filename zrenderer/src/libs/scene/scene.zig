const std = @import("std");
const zm = @import("zmath");

pub const mesh = @import("mesh.zig");
pub const MAX_NAME_LENGTH: u32 = 64;
pub const MAX_NUM_MESHES_PER_NODE: u32 = 8;

pub const NodeStaticType = enum {
    Static,
    Moveable,
};

pub const Node = struct {
    // Number of meshes that make up this node (max 'MAX_NUM_MESHES_PER_NODE' for now)
    num_meshes: u32,
    // Indices of the meshes used by this node inside the MeshData.meshes array
    mesh_indices: [MAX_NUM_MESHES_PER_NODE]u32,

    // Index of the transform of this node inside the Scene.nodes array
    transform_index: u32,

    // Whether this node is static or moveable
    static_type: NodeStaticType,

    // Name of this node, used for debug
    name: [MAX_NAME_LENGTH]u8,
};

pub const SceneFileHeader = struct {
    // Unique 32-bit value to check integrity of the file.
    magic_value: u32,

    // Number of node descriptors following this header.
    num_nodes: u32,

    // Number of transform descriptors following this header.
    num_transforms: u32,
};

// NOTE: For now the scene cannot represent hierarchies (parent - children)
pub const Scene = struct {
    // Flat list of all nodes in this scene
    nodes: std.ArrayList(Node),

    // List of transforms used by the nodes in this scene
    transforms: std.ArrayList(zm.Mat),

    pub fn serialize(scene: *Scene, output_file: std.fs.File) !void {
        var scene_file_header: SceneFileHeader = .{
            .magic_value = 0x87654321,
            .num_nodes = @intCast(u32, scene.nodes.items.len),
            .num_transforms = @intCast(u32, scene.transforms.items.len),
        };

        var slice = @ptrCast([*]u8, &scene_file_header)[0 .. @sizeOf(SceneFileHeader)];
        try output_file.writeAll(std.mem.sliceAsBytes(slice));

        try output_file.writeAll(std.mem.sliceAsBytes(scene.nodes.items[0..]));
        try output_file.writeAll(std.mem.sliceAsBytes(scene.transforms.items[0..]));
    }

    pub fn load(input_file: std.fs.File, allocator: std.mem.Allocator) !Scene {
        var header: SceneFileHeader = undefined;

        var slice = @ptrCast([*]u8, &header)[0 .. @sizeOf(SceneFileHeader)];
        _ = try input_file.readAll(std.mem.asBytes(slice));

        std.debug.assert(header.magic_value == 0x87654321);

        var scene: Scene = .{
            .nodes = std.ArrayList(Node).init(allocator),
            .transforms = std.ArrayList(zm.Mat).init(allocator),
        };
        try scene.nodes.resize(header.num_nodes);
        try scene.transforms.resize(header.num_transforms);

        _ = try input_file.readAll(std.mem.sliceAsBytes(scene.nodes.items[0..]));
        _ = try input_file.readAll(std.mem.sliceAsBytes(scene.transforms.items[0..]));

        return scene;
    }
};