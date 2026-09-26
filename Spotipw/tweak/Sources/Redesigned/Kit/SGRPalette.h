// What a redesigned page takes from its artwork, worked out off the main thread in one pass: the
// colour along the artwork's bottom edge, the field colour made from it, and the blurred bitmaps the
// field (SGRField.h) draws instead of a live blur.
//
// The field colour is the edge colour with its saturation held to 0.55 and its relative luminance to
// 0.07 (0.04 with Increase Contrast). On anything that dark white text is past 8:1 and SGRSecondary
// (white 65%) past 4.5:1, WCAG AA, whatever the hue.
//
// Threading: +paletteForImage: may be called from the main thread only and calls back on it. The work
// runs on one serial background queue; UIImage and CoreImage are read there, UIKit views are not.
#import <UIKit/UIKit.h>

typedef struct {
    // The area a backdrop bitmap covers, in points; CGSizeZero when none is wanted. The bitmap is the
    // artwork filling that area, blurred, dimmed from 0.25 black at the top to 0.45 (0.55 with
    // AMOLED) at 55% of the height, and transparent from 55% down to the bottom, so the field colour
    // under it shows through with no edge.
    CGSize backdropSize;
    // A blurred copy at the artwork's own aspect, transparent down to 55% of its height and opaque
    // from 85%, to lay over the sharp picture with the same aspect fill.
    BOOL dissolve;
    BOOL amoled;
    // The colours of a moving field (SGRFlow.h): the artwork's main colour in each quarter and overall.
    BOOL flow;
} SGRPaletteRequest;

@interface SGRPalette : NSObject
@property (nonatomic, readonly) UIColor *edgeColor;
@property (nonatomic, readonly) UIColor *fieldColor;
@property (nonatomic, readonly) UIImage *backdrop;   // nil unless asked for, at most 160px wide
@property (nonatomic, readonly) UIImage *dissolve;   // nil unless asked for, 96px wide
// nil unless asked for: top left, top right, bottom left, bottom right, then the whole artwork's, each
// the dominant colour there, its saturation lifted a little and its luminance held between
// kFlowLuminanceMin and kFlowLuminanceMax, so white text keeps better than 5.5:1 on any of them.
@property (nonatomic, readonly) NSArray<UIColor *> *flowColors;
// nil to the completion when the image has no bitmap to read (a symbol, a CIImage).
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion;

// `surface` tinted a little towards the artwork's dominant colour (brought down to a luminance of 0.05, then
// 35% of it mixed in), so a tile or row on the surface quietly takes its cover's colour while white text on
// it keeps its contrast. Never dimmer than `surface`: a mix that came out darker is lifted back to its
// luminance keeping its hue, so a near-black cover cannot cost the tile the step of elevation it stands on,
// nor sink it into the grey band SGRAmoled.x turns pure black. nil to the completion when the image has no
// bitmap to read.
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface completion:(void (^)(UIColor *tint))completion;
@end

// Any colour made fit to be a field, the same way the edge colour is: for a colour Spotify hands over
// before the artwork is read. Main thread.
UIColor *SGRFieldColorFor(UIColor *color);
