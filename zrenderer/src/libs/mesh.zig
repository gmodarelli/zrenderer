const std = @import("std");

pub const MAX_LODS: u32 = 8;
pub const MAX_STREAMS: u32 = 8;

// All offsets are relative to the beginning of the data block (excluding headers with Mesh list)
pub const Mesh = struct {
    // Number of LODs in this mesh. Strictly less than MAX_LODS, last LOD offset is used as a marker only.
    num_lods: u32,

    // Number of vertex data streams.
    num_streams: u32,

    // The total count of all previous indices and vertices in this mesh file.
    index_offset: u32,
    vertex_offset: u32,

    // Vertex count for all LODs.
    num_vertices: u32,

    // Offsets to LOD data. Last offset is used as a marker to calculate the size.
    lod_offset: [MAX_LODS]u32,

    // All the data "pointers" for all the streams.
    stream_offset: [MAX_STREAMS]u64,

    // Information about the stream element (size defines everything else, the "semantics" is defined by the sheader).
    stream_element_size: [MAX_STREAMS]u32,

    // Additional information, like mesh name, can be added here

    pub inline fn lodSize(mesh: *Mesh, lod: u32) u64 {
        return mesh.lod_offset[lod + 1] - mesh.lod_offset[lod];
    }
};

pub const MeshFileHeader = struct {
    // Unique 32-bit value to check integrity of the file.
    magic_value: u32,

    // Number of mesh descriptors following this header.
    num_meshes: u32,

    // The offset to combined mesh data (this is the base from which the offsets in individual meshes start).
    data_block_start_offset: u32,

    // How much space index data takes.
    index_data_size: u32,

    // How much space vertex data takes.
    vertex_data_size: u32,
};

pub const MeshData = struct {
    index_data: std.ArrayList(u32),
    vertex_data: std.ArrayList(f32),
    meshes: std.ArrayList(Mesh),
};