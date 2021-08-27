#import "metal.h"
#import <simd/simd.h>

@implementation QemuMetalRenderer
{
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLCommandQueue> _commandQueue;
    id<MTLTexture> _texture;
    id<MTLBuffer> _vertices;
    NSUInteger _numVertices;
    vector_uint2 _viewportSize;
    MTLRenderPassDescriptor *_drawableRenderDescriptor;
    
}


- (id)initWithMetalDevice:(nonnull id<MTLDevice>)device
      drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat
{
    self = [super init];
    if (self)
    {

        _device = device;

        _commandQueue = [_device newCommandQueue];

        _drawableRenderDescriptor = [MTLRenderPassDescriptor new];
        _drawableRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _drawableRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _drawableRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 1, 1, 1);

        {
            NSString *source = @"#include <metal_stdlib>\n\
#include <simd/simd.h>\n\
using namespace metal;\n\
typedef enum AAPLVertexInputIndex\n\
{\
    AAPLVertexInputIndexVertices = 0,\
    AAPLVertexInputIndexUniforms = 1,\
} AAPLVertexInputIndex;\n\
typedef struct\
{\
    vector_float2 position;\
    vector_float3 color;\
} AAPLVertex;\n\
\
typedef struct\
{\
    float scale;\
    vector_uint2 viewportSize;\
} AAPLUniforms;\n\
\
struct RasterizerData\n\
{\
    float4 clipSpacePosition [[position]];\
    float3 color;\
};\n\
\
vertex RasterizerData\n\
vertexShader(uint vertexID [[ vertex_id ]],\
             constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]],\
             constant AAPLUniforms &uniforms  [[ buffer(AAPLVertexInputIndexUniforms) ]])\
{\
    RasterizerData out;\
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;\
    pixelSpacePosition *= uniforms.scale;\
    float2 viewportSize = float2(uniforms.viewportSize);\
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);\
    out.clipSpacePosition.z = 0.0;\
    out.clipSpacePosition.w = 1.0;\
    out.color = vertexArray[vertexID].color;\
    return out;\
}\n\
fragment float4\n\
fragmentShader(RasterizerData in [[stage_in]])\
{\
    return float4(in.color, 1.0);\
}\n\
";
            NSLog(@"source: \n%@", source);
            [_device newLibraryWithSource:source
                                  options:nil 
                        completionHandler:^(id<MTLLibrary> shaderLib, NSError *error) {

                if (!shaderLib) {
                    NSLog(@" ERROR: Couldnt create a default shader library");
                    return;
                }
                id <MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
                if(!vertexProgram)
                {
                    NSLog(@">> ERROR: Couldn't load vertex function from default library");
                    return;
                }

                id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"fragmentShader"];
                if(!fragmentProgram)
                {
                    NSLog(@" ERROR: Couldn't load fragment function from default library");
                    return;
                }

                // Set up a simple MTLBuffer with the vertices, including position and texture coordinates
                static const AAPLVertex quadVertices[] =
                {
                    // Pixel positions, Color coordinates
                    { {  250,  -250 },  { 1.f, 0.f, 0.f } },
                    { { -250,  -250 },  { 0.f, 1.f, 0.f } },
                    { { -250,   250 },  { 0.f, 0.f, 1.f } },

                    { {  250,  -250 },  { 1.f, 0.f, 0.f } },
                    { { -250,   250 },  { 0.f, 0.f, 1.f } },
                    { {  250,   250 },  { 1.f, 0.f, 1.f } },
                };

                // Create a vertex buffer, and initialize it with the vertex data.
                _vertices = [_device newBufferWithBytes:quadVertices
                                                 length:sizeof(quadVertices)
                                                options:MTLResourceStorageModeShared];

                _vertices.label = @"Quad";

                // Create a pipeline state descriptor to create a compiled pipeline state object
                MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

                pipelineDescriptor.label                           = @"MyPipeline";
                pipelineDescriptor.vertexFunction                  = vertexProgram;
                pipelineDescriptor.fragmentFunction                = fragmentProgram;
                pipelineDescriptor.colorAttachments[0].pixelFormat = drawabklePixelFormat;

                NSError *pipelineError;
                _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                         error:&pipelineError];
                if(!_pipelineState)
                {
                    NSLog(@"ERROR: Failed aquiring pipeline state: %@", pipelineError);
                    return;
                }
                NSLog(@"Success: pipeline initialized.");
            }];
        }
    }
    return self;
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer*)metalLayer
{

    // Create a new command buffer for each render pass to the current drawable.
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];

    // If the current drawable is nil, skip rendering this frame
    if(!currentDrawable)
    {
        return;
    }

    _drawableRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    
    id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_drawableRenderDescriptor];


    [renderEncoder setRenderPipelineState:_pipelineState];

    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices ];

    {
        AAPLUniforms uniforms;


        uniforms.scale = 1.0;
        uniforms.viewportSize = _viewportSize;

        [renderEncoder setVertexBytes:&uniforms
                               length:sizeof(uniforms)
                              atIndex:AAPLVertexInputIndexUniforms ];
    }

    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

    [renderEncoder endEncoding];

    [commandBuffer presentDrawable:currentDrawable];

    [commandBuffer commit];
}


- (void)drawableResize:(CGSize)drawableSize
{
    _viewportSize.x = drawableSize.width;
    _viewportSize.y = drawableSize.height;

}
@end
