#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " /* index 0 */ \
    "CBV(b1, visibility = SHADER_VISIBILITY_VERTEX), " /* index 1 */

struct FrameConst {
    float4x4 view_projection;
};
ConstantBuffer<FrameConst> cbv_frame_const : register(b0);

struct DrawConst {
    float4x4 object_to_world;
};
ConstantBuffer<DrawConst> cbv_draw_const : register(b1);

struct Attributes {
    float3 position : POSITION;
    float2 uv : TEXCOORD0;
    float3 color : COLOR;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
};

[RootSignature(ROOT_SIGNATURE)]
void vsMain(Attributes input, out float4 out_position_sv : SV_Position, out float3 out_color : COLOR) {
    const float4x4 object_to_clip = mul(cbv_draw_const.object_to_world, cbv_frame_const.view_projection);
    out_position_sv = mul(float4(input.position, 1.0), object_to_clip);
    out_color = input.color; // vertex color
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(
    float4 position_cs : SV_Position,
    float3 color : COLOR,
    out float4 out_color : SV_Target0
) {
    out_color = float4(color, 1.0);
}
