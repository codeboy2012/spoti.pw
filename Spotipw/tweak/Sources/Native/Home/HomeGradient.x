// Home gradient: a wash behind the top of the Home tab, strongest under the avatar and the pills
// and out by the second shelf, like the gradient Spotify's own Home used to have. The wash is a
// layer inside the page's scroll view, under its content, so it scrolls away with the shelves; the
// base grey the page and the shelves paint over it goes clear in Native/Appearance/Repaint.x, and
// Spotify's own scrim behind the header goes with it, since it would only mute the colour.
//
// Which colour it fades, how strong it is and how far down it reaches come from the choice tables
// in HomeGradientChoices.m, read on every layout pass, so all three apply without restarting
// Spotify. The switch itself is read once, in the %ctor, and still needs a restart.
//
// Tree (trees/home.txt): FunkisViewController.view holds the page, a 402x112 wrapper around
// LiquidGlass.GradientView (the scrim under the avatar and the pills) and HomeHeaderView. Four
// views down, EvoLoadableResourceViewController.view holds the one
// Home_CarouselKit.TouchCancellingCollectionView of the page, full screen and inset 112pt at the
// top for the header, painted #121212; the shelves inside it are collection views of their own,
// painted #121212 as well.
#import "Core/SGCore.h"
#import "Native/Appearance/Repaint.h"
#import "Home.h"

// Colour level behind the header before it starts to go, and colour above the content as well, for
// the rubber band of an overscroll to pull down into.
static const CGFloat kLevelHeight = 52;
static const CGFloat kOverscroll = 600;

// Each table is indexed by the choice of the same name in HomeGradientChoices.m and is as long as
// that list of names.
//
// Sampled off the design: #0B4110 at the top of the screen, level behind the header, gone by 390pt,
// which is Medium at Medium. The other seven colours are that one taken around the wheel.
static const uint32_t kTints[] = {0x0B4110, 0x0B4138, 0x0B2B41, 0x160B41, 0x330B41, 0x410B2E, 0x410B10, 0x412A0B};
static const CGFloat kStrengths[] = {0.62, 1.0, 1.45};
// 0 stands for the whole screen, which is only known once the page has been laid out.
static const CGFloat kHeights[] = {260, 390, 560, 0};

#define SGCount(table) (sizeof(table) / sizeof((table)[0]))

static char kGradientKey, kStrippedKey;

static NSUInteger clamp(NSInteger index, NSUInteger count) {
    if (index < 0) return 0;
    return (NSUInteger)index >= count ? count - 1 : (NSUInteger)index;
}

static UIColor *unpacked(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1];
}

// Strength is the colour itself taken up or down rather than its alpha, so that Subtle stays as
// saturated as Bold instead of washing out into the page behind it.
static uint32_t strengthened(uint32_t rgb, CGFloat factor) {
    uint32_t out = 0;
    for (int shift = 16; shift >= 0; shift -= 8) {
        uint32_t channel = (uint32_t)round(MIN(255.0, ((rgb >> shift) & 0xFF) * factor));
        out |= channel << shift;
    }
    return out;
}

// A view of its own, so the wash follows the page's layout passes instead of animating itself
// through CoreAnimation whenever the inset changes.
@interface SGHomeGradientView : UIView
- (void)paintColor:(uint32_t)color span:(CGFloat)span;
@end

@implementation SGHomeGradientView {
    uint32_t _color;
    CGFloat _span;
}

+ (Class)layerClass {
    return CAGradientLayer.class;
}

// The page lays out on every scroll, so a pass that changes neither the colour nor how far it
// reaches leaves the layer alone.
- (void)paintColor:(uint32_t)color span:(CGFloat)span {
    if (color == _color && span == _span) return;
    _color = color;
    _span = span;
    UIColor *tint = unpacked(color);
    CGFloat total = kOverscroll + span;
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    gradient.colors = @[(id)tint.CGColor, (id)tint.CGColor, (id)[tint colorWithAlphaComponent:0].CGColor];
    gradient.locations = @[@0, @((kOverscroll + kLevelHeight) / total), @1];
}

@end

// The shelves and the shortcuts grid are lists of their own, each painting the base surface over
// the wash. A cell paints itself before the page puts it in, where the hook in Native/Appearance/Repaint.x cannot
// see that it belongs to Home, so every cell is stripped once as it turns up; the repaints it
// takes later, in the page by then, go through the hook. The page's own paint is behind the wash.
static void stripCells(UIScrollView *list) {
    for (UIView *cell in list.subviews) {
        if (objc_getAssociatedObject(cell, &kStrippedKey)) continue;
        objc_setAssociatedObject(cell, &kStrippedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGForEachView(cell, ^(UIView *v) {
            if (SGIsBaseSurface(v.layer.backgroundColor)) v.layer.backgroundColor = NULL;
        });
    }
}

static SGHomeGradientView *gradientIn(UIScrollView *list) {
    SGHomeGradientView *view = objc_getAssociatedObject(list, &kGradientKey);
    if (!view) {
        view = [SGHomeGradientView new];
        view.userInteractionEnabled = NO;
        // A list puts its cells in at index 0, so that its scroll indicators stay on top of them;
        // the subview order alone would push the wash over the content. Depth settles it instead.
        view.layer.zPosition = -1;
        objc_setAssociatedObject(list, &kGradientKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"home gradient behind %@", NSStringFromClass(list.class));
    }
    if (view.superview != list) [list insertSubview:view atIndex:0];
    return view;
}

// Content coordinates: the content starts below the header, so the wash starts at minus the inset,
// where the top of the screen is when the list sits still.
static void layoutGradient(UIScrollView *list) {
    SGHomeGradientView *view = gradientIn(list);
    if (sg_homeRoot != list) sg_homeRoot = list;
    stripCells(list);

    CGFloat height = kHeights[clamp(SGHomeChoiceValue(SGHomeChoiceHeight), SGCount(kHeights))];
    CGFloat span = height > 0 ? height : list.bounds.size.height;
    uint32_t color = strengthened(kTints[clamp(SGHomeChoiceValue(SGHomeChoiceTint), SGCount(kTints))],
                                  kStrengths[clamp(SGHomeChoiceValue(SGHomeChoiceStrength), SGCount(kStrengths))]);

    CGRect frame = CGRectMake(0, -kOverscroll - list.adjustedContentInset.top,
                              list.bounds.size.width, kOverscroll + span);
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
    [view paintColor:color span:span];
}

// The one collection view of the page; the shelves are collection views nested inside it.
static UIScrollView *pageList(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) return (UIScrollView *)sub;
    }
    return nil;
}

%hook _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIScrollView *list = pageList(((UIViewController *)self).viewIfLoaded);
    if (list) layoutGradient(list);
}
%end

// The list lays out on every scroll too, which is when the bars change its inset. Album, artist
// and playlist pages are lists of the same class, hence the check for the one Home owns.
%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    if ((UIView *)self == sg_homeRoot) layoutGradient((UIScrollView *)self);
}
%end

// The scrim is a gradient view one view under the page's own; the gradients of the cards sit far
// deeper than that, so two levels cannot reach them.
%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews {
    %orig;
    for (UIView *wrapper in ((UIViewController *)self).viewIfLoaded.subviews) {
        for (UIView *view in wrapper.subviews) {
            if ([NSStringFromClass(view.class) containsString:@"GradientView"]) view.hidden = YES;
        }
    }
}
%end

%ctor {
    if (!SGNativeUI() || !SGFlag(SGKeyHomeGradient, NO)) return;
    %init;
    SGRequireClasses(@[
        @"_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
        @"_TtC19Home_FunkisPageImpl20FunkisViewController",
    ]);
}
