#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

@protocol QemuMetalViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;

- (void)renderToMetalLayer:(CAMetalLayer *)metalLayer;

@end


@interface QemuMetalRenderer: NSObject<QemuMetalViewDelegate>
- (id)initWithMetalDevice:(id<MTLDevice>)device
      drawablePixelFormat:(MTLPixelFormat)drawabklePixelFormat;

- (void)updateDisplayTextureWithBuffer:(const uint8_t*)srcBytes
                                     x:(int)x
                                     y:(int)y
                                 width:(int)width
                                height:(int)height
                                stride:(int)stride;
- (void)defineCursorTextureWithBuffer:(const void *)srcBytes
                                width:(int)width
                               height:(int)height
                               stride:(int)stride;       
- (void)setCursorVisible:(BOOL)visibility x:(int)x y:(int)y;
- (void)renderToMetalLayer:(CAMetalLayer*)metalLayer;

- (void)drawableResize:(CGSize)drawableSize;
- (void)setTitleHeight:(NSUInteger)h;
- (NSUInteger)getTitleHeight;
- (void)setTitleBlurred:(BOOL)blurred;
@end

