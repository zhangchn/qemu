#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

@protocol QemuMetalViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;

- (void)renderToMetalLayer:(CAMetalLayer *)metalLayer;

@end


@interface QemuMetalRenderer: NSObject<QemuMetalViewDelegate>

- (id)initWithMetalDevice:(id<MTLDevice>)device
      drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat;

- (void)renderToMetalLayer:(CAMetalLayer*)metalLayer;

- (void)drawableResize:(CGSize)drawableSize;

@end

typedef enum AAPLVertexInputIndex
{
    AAPLVertexInputIndexVertices = 0,
    AAPLVertexInputIndexUniforms = 1,
} AAPLVertexInputIndex;

typedef struct
{
    // Positions in pixel space (i.e. a value of 100 indicates 100 pixels from the origin/center)
    vector_float2 position;

    // 2D texture coordinate
    vector_float3 color;
} AAPLVertex;

typedef struct
{
    float scale;
    vector_uint2 viewportSize;
} AAPLUniforms;

