#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

@protocol QemuMetalViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;

- (void)renderToMetalLayer:(CAMetalLayer *)metalLayer;

@end


@interface QemuMetalRenderer: NSObject<QemuMetalViewDelegate>
- (id<MTLTexture>)prepareTexture:(CGSize)size;
- (id)initWithMetalDevice:(id<MTLDevice>)device
      drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat;

- (void)renderToMetalLayer:(CAMetalLayer*)metalLayer;

- (void)drawableResize:(CGSize)drawableSize;
- (id<MTLTexture>) texture;
@end

typedef enum AAPLVertexInputIndex
{
    AAPLVertexInputIndexVertices = 0,
    AAPLVertexInputIndexViewportSize = 1,
} AAPLVertexInputIndex;

// Texture index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API texture set calls
typedef enum AAPLTextureIndex
{
    AAPLTextureIndexBaseColor = 0,
} AAPLTextureIndex;

//  This structure defines the layout of each vertex in the array of vertices set as an input to the
//    Metal vertex shader.  Since this header is shared between the .metal shader and C code,
//    you can be sure that the layout of the vertex array in the code matches the layout that
//    the vertex shader expects

typedef struct
{
    // Positions in pixel space. A value of 100 indicates 100 pixels from the origin/center.
    vector_float2 position;

    // 2D texture coordinate
    vector_float2 textureCoordinate;
} AAPLVertex;

