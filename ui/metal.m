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

- (id<MTLTexture>) texture
{
    return _texture;
}

- (id)initWithMetalDevice:(nonnull id<MTLDevice>)device
      drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat
{
    self = [super init];
    if (self)
    {

        _device = device;

        _commandQueue = [_device newCommandQueue];
        _viewportSize.x = 640;
        _viewportSize.y = 480;

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
    AAPLVertexInputIndexViewportSize = 1,\
} AAPLVertexInputIndex;\n\
typedef enum AAPLTextureIndex\n\
{\n\
    AAPLTextureIndexBaseColor = 0,\n\
} AAPLTextureIndex;\n\
typedef struct\n\
{\
    vector_float2 position;\
    vector_float2 textureCoordinate;\
} AAPLVertex;\n\
struct RasterizerData\n\
{\
    float4 position [[position]];\
    float2 textureCoordinate;\
};\n\
\
vertex RasterizerData\n\
vertexShader(uint vertexID [[ vertex_id ]],\n\
             constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]]\n\
             )\n\
{\n\
    RasterizerData out;\n\
    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);\n\
    out.position.xy = vertexArray[vertexID].position.xy;\n\
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;\n\
    return out;\n\
}\n\
fragment float4 \n\
samplingShader(RasterizerData in [[stage_in]],\n\
               texture2d<half> colorTexture [[ texture(AAPLTextureIndexBaseColor) ]])\n\
{\n\
    constexpr sampler textureSampler (mag_filter::linear,\n\
                                      min_filter::linear);\n\
    const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);\n\
    float4 x = float4(colorSample);\n\
    return x; // float4(colorSample);\n\
}\n\
";
            NSLog(@"source: \n%@", source);
            void *placeholder = malloc(_viewportSize.x * _viewportSize.y * 4);
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

                id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"samplingShader"];
                if(!fragmentProgram)
                {
                    NSLog(@" ERROR: Couldn't load fragment function from default library");
                    return;
                }

                // Set up a simple MTLBuffer with the vertices, including position and texture coordinates
                static const AAPLVertex quadVertices[] =
                {
                    // Pixel positions, texture coordinates
                    { {  1.f,  -1.f },  { 1.f, 1.f } },
                    { { -1.f,  -1.f },  { 0.f, 1.f } },
                    { { -1.f,   1.f },  { 0.f, 0.f } },

                    { {  1.f,  -1.f },  { 1.f, 1.f } },
                    { { -1.f,   1.f },  { 0.f, 0.f } },
                    { {  1.f,   1.f },  { 1.f, 0.f } },
                };

                // Create a vertex buffer, and initialize it with the vertex data.
                _vertices = [_device newBufferWithBytes:quadVertices
                                                 length:sizeof(quadVertices)
                                                options:MTLResourceStorageModeShared];

                _vertices.label = @"Quad";
                _numVertices = sizeof(quadVertices) / sizeof(AAPLVertex);

                CGSize s = CGSizeMake(_viewportSize.x, _viewportSize.y);
                [self prepareTexture:s];
                [_texture replaceRegion:MTLRegionMake2D(0, 0, _viewportSize.x, _viewportSize.y)
                            mipmapLevel:0
                              withBytes:placeholder
                            bytesPerRow:_viewportSize.x * 4];
                // Create a pipeline state descriptor to create a compiled pipeline state object
                MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

                pipelineDescriptor.label                           = @"MyPipeline";
                pipelineDescriptor.vertexFunction                  = vertexProgram;
                pipelineDescriptor.fragmentFunction                = fragmentProgram;
                pipelineDescriptor.colorAttachments[0].pixelFormat = drawablePixelFormat;

                NSError *pipelineError;
                _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor
                                                                         error:&pipelineError];
                if(!_pipelineState)
                {
                    NSLog(@"ERROR: Failed aquiring pipeline state: %@", pipelineError);
                    return;
                }
                [pipelineDescriptor release];
                NSLog(@"Success: pipeline initialized.");
            }];
        }
    }
    return self;
}

- (void)prepareTexture:(CGSize)size
{
    NSLog(@"prepareTexture: %@", NSStringFromSize(size));
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = size.width;
    textureDescriptor.height = size.height;
    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
    [textureDescriptor autorelease];
    _texture = texture;
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer*)metalLayer
{

    // NSLog(@"renderToMetalLayer");
    // Create a new command buffer for each render pass to the current drawable.
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];

    // If the current drawable is nil, skip rendering this frame
    if(!currentDrawable || !_pipelineState || !_texture)
    {
        return;
    }
    // NSLog(@"_viewportSize: %d, %d", _viewportSize.x, _viewportSize.y);
    // NSLog(@"_numVertices: %d", _numVertices);

    _drawableRenderDescriptor.colorAttachments[0].texture = currentDrawable.texture;
    
    id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:_drawableRenderDescriptor];
    [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];


    [renderEncoder setRenderPipelineState:_pipelineState];

    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:AAPLVertexInputIndexVertices ];

    [renderEncoder setVertexBytes:&_viewportSize
                           length:sizeof(_viewportSize)
                          atIndex:AAPLVertexInputIndexViewportSize ];
    [renderEncoder setFragmentTexture:_texture
                              atIndex:AAPLTextureIndexBaseColor];

    
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:_numVertices];

    [renderEncoder endEncoding];

    [commandBuffer presentDrawable:currentDrawable];

    [commandBuffer commit];
}


- (void)drawableResize:(CGSize)drawableSize
{
    NSLog(@"drawableResize: new size: %@", NSStringFromSize(drawableSize));
    if (drawableSize.width != _viewportSize.x || drawableSize.height != _viewportSize.y) {
        NSLog(@"drawableResize: prepare texture");
        [self prepareTexture:drawableSize];
    }
    _viewportSize.x = drawableSize.width;
    _viewportSize.y = drawableSize.height;
}
@end
