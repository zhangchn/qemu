#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;
typedef enum QEMUVertexInputIndex
{
    QEMUVertexInputIndexVertices = 0,
    QEMUVertexInputIndexViewportSize = 1,
} QEMUVertexInputIndex;
typedef enum QEMUTextureIndex
{
    QEMUTextureIndexBaseColor = 0,
    QEMUTextureIndexCursorColor = 1,
} QEMUTextureIndex;
typedef struct
{
    vector_float3 position;    
    vector_float2 textureCoordinate;
} QEMUVertex;
struct RasterizerData
{
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant QEMUVertex *vertexArray [[ buffer(QEMUVertexInputIndexVertices) ]])
{
    RasterizerData out;
    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xyz = vertexArray[vertexID].position.xyz;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

fragment float4
samplingShader(RasterizerData in [[stage_in]],
               texture2d<half> colorTexture [[ texture(QEMUTextureIndexBaseColor) ]],
               texture2d<half> cursorTexture [[ texture(QEMUTextureIndexCursorColor) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    constexpr sampler cursorTextureSampler (mag_filter::linear,
                                            min_filter::linear);
    half4 colorSample;
    if (in.position.z > 0.5) {
        colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);
        colorSample.a = 1.0;
    } else {
        colorSample = cursorTexture.sample(cursorTextureSampler, in.textureCoordinate);
    }
    return float4(colorSample);
}
