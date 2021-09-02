#import "metal.h"
#import <simd/simd.h>

// definition shared with shaders

typedef enum QEMUVertexInputIndex
{
    QEMUVertexInputIndexVertices = 0,
    QEMUVertexInputIndexViewportSize = 1,
} QEMUVertexInputIndex;

// Texture index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API texture set calls
typedef enum QEMUTextureIndex
{
    QEMUTextureIndexBaseColor = 0,
    QEMUTextureIndexCursorColor = 1,
} QEMUTextureIndex;

//  This structure defines the layout of each vertex in the array of vertices set as an input to the
//    Metal vertex shader.  Since this header is shared between the .metal shader and C code,
//    you can be sure that the layout of the vertex array in the code matches the layout that
//    the vertex shader expects

typedef struct
{
    // Positions in pixel space with depth. A value of 100 indicates 100 pixels from the origin/center.
    vector_float3 position;

    // 2D texture coordinate
    vector_float2 textureCoordinate;
} QEMUVertex;


@implementation QemuMetalRenderer
{
    id<MTLDevice> _device;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLCommandQueue> _commandQueue;
    id<MTLTexture> _depthTarget;
    id<MTLTexture> _texture;
    id<MTLTexture> _cursorTexture;
    id<MTLTexture> _cursorTexturePlaceholder;
    id<MTLBuffer> _vertices;
    NSUInteger _numVertices;
    vector_uint2 _viewportSize;
    vector_uint4 _cursorRect;
    BOOL _cursorVisible;
    MTLRenderPassDescriptor *_drawableRenderDescriptor;
    id<MTLDepthStencilState> _depthState;
    
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
        _cursorRect.x = 0;
        _cursorRect.y = 0;
        _cursorRect.z = 1;
        _cursorRect.w = 1;
        _cursorVisible = NO;

        _drawableRenderDescriptor = [MTLRenderPassDescriptor new];
        _drawableRenderDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _drawableRenderDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        _drawableRenderDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        _drawableRenderDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        _drawableRenderDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
        _drawableRenderDescriptor.depthAttachment.clearDepth = 1.0;
        

        MTLDepthStencilDescriptor *depthDescriptor = [MTLDepthStencilDescriptor new];
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
        depthDescriptor.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
        {
            
            NSError *sourceErr;
            NSString *source = [NSString stringWithContentsOfFile:@"/tmp/1.metal"
                                                         encoding:NSUTF8StringEncoding
                                                            error:&sourceErr];
            
            if (sourceErr) { NSLog(@"error: %@", sourceErr);} else {NSLog(@"source: \n%@", source);}
            void *placeholder = malloc(_viewportSize.x * _viewportSize.y * 4);
            [_device newLibraryWithSource:source
                                  options:nil 
                        completionHandler:^(id<MTLLibrary> shaderLib, NSError *error) {

                if (!shaderLib) {
                    NSLog(@" ERROR: Couldnt create a default shader library");
                    NSLog(@"%@", error);
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

                /*
                float cursorMaxX = 128.0 / 640.0 - 1.0;
                float cursorMinX = -1.0;
                float cursorMaxY = 1.0;
                float cursorMinY = 1.0 - 128.0 / 480.0;
                */

                // Set up a simple MTLBuffer with the vertices, including position and texture coordinates
                static const QEMUVertex quadVertices[] =
                {
                    // display vertex positions, texture coordinates
                    { {  1.f,  -1.f,  0.9f },  { 1.f, 1.f } },
                    { { -1.f,  -1.f,  0.9f },  { 0.f, 1.f } },
                    { { -1.f,   1.f,  0.9f },  { 0.f, 0.f } },

                    { {  1.f,  -1.f,  0.9f },  { 1.f, 1.f } },
                    { { -1.f,   1.f,  0.9f },  { 0.f, 0.f } },
                    { {  1.f,   1.f,  0.9f },  { 1.f, 0.f } },
                    
                    // cursor vertex positions, texture coordinates
                    { {  -0.8, 0.7333333, 0.1f },  { 1.f, 1.f } },
                    { {  -1.f, 0.7333333, 0.1f },  { 0.f, 1.f } },
                    { {  -1.f, 1.f, 0.1f },  { 0.f, 0.f } },

                    { {  -0.8, 0.7333333, 0.1f },  { 1.f, 1.f } },
                    { {  -1.f, 1.f, 0.1f },  { 0.f, 0.f } },
                    { {  -0.8, 1.f, 0.1f },  { 1.f, 0.f } },

                };

                // Create a vertex buffer, and initialize it with the vertex data.
                _vertices = [_device newBufferWithBytes:quadVertices
                                                 length:sizeof(quadVertices)
                                                options:MTLResourceStorageModeShared];

                _vertices.label = @"Quad";
                _numVertices = sizeof(quadVertices) / sizeof(QEMUVertex);

                CGSize s = CGSizeMake(_viewportSize.x, _viewportSize.y);
                [self prepareTexture:s];
                [_texture replaceRegion:MTLRegionMake2D(0, 0, _viewportSize.x, _viewportSize.y)
                            mipmapLevel:0
                              withBytes:placeholder
                            bytesPerRow:_viewportSize.x * 4];

                // cursor placeholder:
                MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
                textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
                textureDescriptor.width = 1;
                textureDescriptor.height = 1;
                _cursorTexturePlaceholder = [_device newTextureWithDescriptor:textureDescriptor];
                [textureDescriptor release];
                uint8_t cursorPlaceholderBytes[] = {0, 0, 0, 0};
                [_cursorTexturePlaceholder  replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                                              mipmapLevel:0
                                                withBytes:cursorPlaceholderBytes
                                              bytesPerRow:4];
                /*
                [self defineCursorTextureWithBuffer:placeholder 
                                              width:_cursorRect.z 
                                             height:_cursorRect.w 
                                             stride:_cursorRect.z * 4];
                                             */
                // Create a pipeline state descriptor to create a compiled pipeline state object
                MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

                pipelineDescriptor.label                           = @"MyPipeline";
                pipelineDescriptor.vertexFunction                  = vertexProgram;
                pipelineDescriptor.fragmentFunction                = fragmentProgram;
                pipelineDescriptor.colorAttachments[0].pixelFormat = drawablePixelFormat;
                pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
                pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
                pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorSourceAlpha;
                pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
                pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

                pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

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
    [renderEncoder setDepthStencilState:_depthState];

    [renderEncoder setVertexBuffer:_vertices
                            offset:0
                           atIndex:QEMUVertexInputIndexVertices ];

    [renderEncoder setVertexBytes:&_viewportSize
                           length:sizeof(_viewportSize)
                          atIndex:QEMUVertexInputIndexViewportSize ];
    [renderEncoder setFragmentTexture:_texture
                              atIndex:QEMUTextureIndexBaseColor];
    
    [renderEncoder setFragmentTexture:_cursorVisible ? _cursorTexture : _cursorTexturePlaceholder
                              atIndex:QEMUTextureIndexCursorColor];

    
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

    MTLTextureDescriptor *depthTargetDescriptor = [MTLTextureDescriptor new];
    depthTargetDescriptor.width       = drawableSize.width;
    depthTargetDescriptor.height      = drawableSize.height;
    depthTargetDescriptor.pixelFormat = MTLPixelFormatDepth32Float;
    depthTargetDescriptor.storageMode = MTLStorageModePrivate;
    depthTargetDescriptor.usage       = MTLTextureUsageRenderTarget;

    _depthTarget = [_device newTextureWithDescriptor:depthTargetDescriptor];

    _drawableRenderDescriptor.depthAttachment.texture = _depthTarget;
}

- (void)updateDisplayTextureWithBuffer:(const uint8_t*)srcBytes
                                     x:(int)x
                                     y:(int)y
                                 width:(int)width
                                height:(int)height
                                stride:(int)stride
{
    MTLRegion region = MTLRegionMake2D(x, y, width, height);
    [_texture replaceRegion:region
                mipmapLevel:0
                  withBytes:srcBytes
                bytesPerRow:stride];
}

- (void)defineCursorTextureWithBuffer:(const void *)srcBytes
                                width:(int)width
                               height:(int)height
                               stride:(int)stride
{
    //NSLog(@"defineCursorTexture: %d %d", width, height);
    if (width != _cursorRect.z || height != _cursorRect.w || !_cursorTexture) {
        //NSLog(@"prepare cursor texture");
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.width = width;
        textureDescriptor.height = height;
        id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
        [textureDescriptor release];
        [_cursorTexture release];
        _cursorTexture = texture;
        _cursorRect.z = width;
        _cursorRect.w = height;
    }
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    /*
    uint8_t *test = malloc(stride * height);
    int j;
    for (j = 0; j < stride * height; j++)
        test[j] = (j % 2) ? 255 : 0;

        */
    [_cursorTexture replaceRegion:region
                      mipmapLevel:0
                        withBytes:srcBytes
                      bytesPerRow:stride];
    // free(test);
    /*
    int i, j, k;
    for (k = 0; k < 4; k++)
        for (j = 0; j < height; j++) {
            char line[width];
            for (i = 0; i < width; i++) {
                char pix_rep[] = {'_', '+', '#', '@'};
                line[i] = pix_rep[srcBytes[j * stride + i * 4 + k] / 64];
            }
            NSString *lineString = [[NSString alloc] initWithBytes:line length:width encoding:NSASCIIStringEncoding];
            NSLog(@"%d:%3d %@", k, j, lineString);
            [lineString release];
        }
        */
}

- (void)setCursorVisible:(BOOL)visibility x:(int)x y:(int)y
{
    _cursorVisible = visibility;
    _cursorRect.x = MIN(MAX(x, 0), _viewportSize.x);
    _cursorRect.y = MIN(MAX(y, 0), _viewportSize.y);
    // update cursor quad position
    float cursorMaxX = (_cursorRect.x + _cursorRect.z) * 2.0 / _viewportSize.x - 1.0;
    float cursorMinX = _cursorRect.x * 2.0 / _viewportSize.x - 1.0;
    float cursorMaxY = 1.0 - _cursorRect.y * 2.0 / _viewportSize.y;
    float cursorMinY = 1.0 - (_cursorRect.y + _cursorRect.w) * 2.0 / _viewportSize.y;
    // NSLog(@"%.1f, %.1f, %.1f, %.1f", cursorMinX, cursorMaxY, x, y);

    QEMUVertex *quadVertices = [_vertices contents];
    if (quadVertices) {
        quadVertices[6].position.x  =  cursorMaxX;
        quadVertices[6].position.y  =  cursorMinY;
        quadVertices[7].position.x  =  cursorMinX;
        quadVertices[7].position.y  =  cursorMinY;
        quadVertices[8].position.x  =  cursorMinX;
        quadVertices[8].position.y  =  cursorMaxY;

        quadVertices[9].position.x  =  cursorMaxX;
        quadVertices[9].position.y  =  cursorMinY;
        quadVertices[10].position.x =  cursorMinX;
        quadVertices[10].position.y =  cursorMaxY;
        quadVertices[11].position.x =  cursorMaxX;
        quadVertices[11].position.y =  cursorMaxY;
    }
}
@end
