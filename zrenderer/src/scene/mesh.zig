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

pub const VertexData = struct {
    position: [3]f32,
    uv: [2]f32,
    color: [4]f32,
    normal: [3]f32,
    tangent: [4]f32,
};

pub const MeshData = struct {
    index_data: std.ArrayList(u32),
    vertex_data: std.ArrayList(f32),
    meshes: std.ArrayList(Mesh),

    pub fn serialize(mesh_data: *MeshData, output_file: std.fs.File) !void {
        var mesh_file_header: MeshFileHeader = .{
            .magic_value = 0x12345678,
            .num_meshes = @intCast(u32, mesh_data.meshes.items.len),
            .data_block_start_offset = @intCast(u32, @sizeOf(MeshFileHeader) + mesh_data.meshes.items.len * @sizeOf(Mesh)),
            .index_data_size = @intCast(u32, @sizeOf(u32) * mesh_data.index_data.items.len),
            .vertex_data_size = @intCast(u32, @sizeOf(f32) * mesh_data.vertex_data.items.len),
        };

        var slice = @ptrCast([*]u8, &mesh_file_header)[0 .. @sizeOf(MeshFileHeader)];
        try output_file.writeAll(std.mem.sliceAsBytes(slice));

        try output_file.writeAll(std.mem.sliceAsBytes(mesh_data.meshes.items[0..]));
        try output_file.writeAll(std.mem.sliceAsBytes(mesh_data.vertex_data.items[0..]));
        try output_file.writeAll(std.mem.sliceAsBytes(mesh_data.index_data.items[0..]));
    }

    pub fn load(input_file: std.fs.File, allocator: std.mem.Allocator) !MeshData {
        var header: MeshFileHeader = undefined;

        var slice = @ptrCast([*]u8, &header)[0 .. @sizeOf(MeshFileHeader)];
        var bytes_read = try input_file.readAll(std.mem.asBytes(slice));
        std.debug.assert(bytes_read == @sizeOf(MeshFileHeader));

        std.debug.assert(header.magic_value == 0x12345678);

        var mesh_data: MeshData = .{
            .index_data = std.ArrayList(u32).init(allocator),
            .vertex_data = std.ArrayList(f32).init(allocator),
            .meshes = std.ArrayList(Mesh).init(allocator),
        };
        try mesh_data.meshes.resize(header.num_meshes);
        try mesh_data.vertex_data.resize(header.vertex_data_size / 4);
        try mesh_data.index_data.resize(header.index_data_size / 4);

        bytes_read = try input_file.readAll(std.mem.sliceAsBytes(mesh_data.meshes.items[0..]));
        std.debug.assert(bytes_read == header.num_meshes * @sizeOf(Mesh));

        bytes_read = try input_file.readAll(std.mem.sliceAsBytes(mesh_data.vertex_data.items[0..]));
        std.debug.assert(bytes_read == header.vertex_data_size);

        bytes_read = try input_file.readAll(std.mem.sliceAsBytes(mesh_data.index_data.items[0..]));
        std.debug.assert(bytes_read == header.index_data_size);

        return mesh_data;
    }

    pub fn unload(mesh_data: *MeshData, _: std.mem.Allocator) void {
        mesh_data.meshes.deinit();
        mesh_data.vertex_data.deinit();
        mesh_data.index_data.deinit();
    }
};