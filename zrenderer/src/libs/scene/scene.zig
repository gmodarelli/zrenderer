const std = @import("std");
const zm = @import("zmath");

pub const mesh = @import("mesh.zig");
pub const MAX_NAME_LENGTH: u32 = 64;
pub const MAX_NUM_MESHES_PER_NODE: u32 = 8;

pub const Node = struct {
    // Number of meshes that make up this node (max 'MAX_NUM_MESHES_PER_NODE' for now)
    num_meshes: u32,
    // Indices of the meshes used by this node inside the MeshData.meshes array
    mesh_indices: [MAX_NUM_MESHES_PER_NODE]u32,

    // Index of the transform of this node inside the Scene.nodes array
    transform_index: u32,

    // Name of this node, used for debug
    name: [MAX_NAME_LENGTH]u8,
};

// NOTE: For now the scene cannot represent hierarchies (parent - children)
pub const Scene = struct {
    // Flat list of all nodes in this scene
    nodes: std.ArrayList(Node),

    // List of transforms used by the nodes in this scene
    transforms: std.ArrayList(zm.Mat),
};