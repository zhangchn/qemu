#import "metal.h"
#import <simd/simd.h>

// definition shared with shaders

typedef enum QEMUVertexInputIndex
{
    QEMUVertexInputIndexVertices = 0,
    QEMUVertexInputIndexViewportSize = 1,
} QEMUVertexInputIndex;

// Texture index values
// Two textures were created for the base plane and the cursor plane, respectively
typedef enum QEMUTextureIndex
{
    QEMUTextureIndexBaseColor = 0,
    QEMUTextureIndexCursorColor = 1,
} QEMUTextureIndex;

typedef struct
{
    // Positions in NDC, depth to distinguish vertices from base/cursor quad.
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
    id<MTLTexture> _baseTexture;
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
        _cursorRect.z = 64;
        _cursorRect.w = 64;
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
        [depthDescriptor release];
        {
            
            NSString *execPath = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
            NSArray *shaderSearchPaths = @[
                execPath,
                [[execPath stringByAppendingString:@"../share/qemu/"] stringByStandardizingPath],
                @"/usr/local/share/qemu"
            ];
            __block NSString *source;
            [shaderSearchPaths enumerateObjectsUsingBlock:^(NSString *path, NSUInteger idx, BOOL *stop) {
                NSString *shaderPath = [path stringByAppendingPathComponent:@"metal_shader.metal"];
                NSError *sourceErr = NULL;
                source = [NSString stringWithContentsOfFile:shaderPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:&sourceErr];
                if (!source) {
                    NSLog(@"error reading %@: %@", shaderPath, sourceErr);
                } else {
                    *stop = YES;
                    NSLog(@"using shader source at %@", shaderPath);
                    // NSLog(@"source: %@", source);
                    [source retain];
                }
            }];
            
            if (!source) {
                return nil;
            }
            [source autorelease];
            void *placeholder = malloc(_viewportSize.x * _viewportSize.y * 4);
            NSError *libError;
            id<MTLLibrary> shaderLib = [_device newLibraryWithSource:source
                                                             options:nil
                                                               error:&libError];
            
            if (!shaderLib) {
                NSLog(@" ERROR: Couldnt create a default shader library");
                NSLog(@"%@", libError);
                return nil;
            }
            id <MTLFunction> vertexProgram = [shaderLib newFunctionWithName:@"vertexShader"];
            if(!vertexProgram)
            {
                NSLog(@">> ERROR: Couldn't load vertex function from default library");
                return nil;
            }
            
            id <MTLFunction> fragmentProgram = [shaderLib newFunctionWithName:@"samplingShader"];
            [shaderLib release];
            if(!fragmentProgram)
            {
                NSLog(@" ERROR: Couldn't load fragment function from default library");
                return nil;
            }
            
            /*
             cursor rect calculated from Qemu Screen metrics:
             MaxX = 2 * width / 640.0 - 1.0;
             MinX = -1.0;
             MaxY = 1.0;
             MinY = 1.0 - 2 * height / 480.0;
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
            [_baseTexture replaceRegion:MTLRegionMake2D(0, 0, _viewportSize.x, _viewportSize.y)
                            mipmapLevel:0
                              withBytes:placeholder
                            bytesPerRow:_viewportSize.x * 4];
            
            // prepare cursor placeholder texture
            // A buffer of 1x1 transparent pixel could suffice for invisibility of cursor state.
            MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
            textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
            textureDescriptor.width = 1;
            textureDescriptor.height = 1;
            _cursorTexturePlaceholder = [_device newTextureWithDescriptor:textureDescriptor];
            [textureDescriptor release];
            uint8_t cursorPlaceholderBytes[] = {0, 0, 0, 0};
            [_cursorTexturePlaceholder replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                                         mipmapLevel:0
                                           withBytes:cursorPlaceholderBytes
                                         bytesPerRow:4];
            
            // Create a pipeline state descriptor to create a compiled pipeline state object
            MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            
            pipelineDescriptor.label                           = @"QemuMetalPipeline";
            pipelineDescriptor.vertexFunction                  = vertexProgram;
            pipelineDescriptor.fragmentFunction                = fragmentProgram;
            pipelineDescriptor.colorAttachments[0].pixelFormat = drawablePixelFormat;
            // The settings for cursor-base blending
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
                return nil;
            }
            [pipelineDescriptor release];
            [vertexProgram release];
            [fragmentProgram release];
            NSLog(@"Success: pipeline initialized.");
        }
    }
    return self;
}

- (void)prepareTexture:(CGSize)size
{
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = size.width;
    textureDescriptor.height = size.height;
    [_baseTexture release];
    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
    [textureDescriptor release];
    _baseTexture = texture;
}

- (void)renderToMetalLayer:(nonnull CAMetalLayer*)metalLayer
{
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    id<CAMetalDrawable> currentDrawable = [metalLayer nextDrawable];
    
    if(!currentDrawable || !_pipelineState || !_baseTexture)
    {
        return;
    }
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
    [renderEncoder setFragmentTexture:_baseTexture
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
    // NSLog(@"drawableResize: %dx%d -> %.0fx%.0f %@", _viewportSize.x, _viewportSize.y, drawableSize.width, drawableSize.height, [NSThread callStackSymbols]);
    if (drawableSize.width != _viewportSize.x || drawableSize.height != _viewportSize.y) {
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
    [_baseTexture replaceRegion:region
                    mipmapLevel:0
                      withBytes:srcBytes
                    bytesPerRow:stride];
}

- (void)defineCursorTextureWithBuffer:(const void *)srcBytes
                                width:(int)width
                               height:(int)height
                               stride:(int)stride
{
    if (width != _cursorRect.z || height != _cursorRect.w || !_cursorTexture) {
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
    [_cursorTexture replaceRegion:region
                      mipmapLevel:0
                        withBytes:srcBytes
                      bytesPerRow:stride];
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
