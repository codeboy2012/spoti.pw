// Page transitions: coming back to a page that has no navigation bar of its own — Home, the full
// screen search — the page is laid out 54pt low, and drops into place about half a second later.
//
// Spotify's Liquid Glass path is what does it. -[SPNavigationController
// navigationController:willShowViewController:animated:] settles what the bar is to do, and for a
// page that wants it gone the call that would do it is -[SPNavigationController
// setNavigationBarHidden:]. With +[SPTLiquidGlass isEnabled] answering yes and a transition
// running, that call is not made there: the bar's alpha alone is animated away and the call is left
// to the transition's completion block. So the bar is invisible but still on the controller for the
// whole transition and a while after — measured at 534ms, from willShow to the bar going — and its
// 54pt still count against the page: Home's header lands at y 116 instead of 62 and its list is
// inset 166 instead of 112 (trees/test5.txt against trees/test6.txt, the same screen a moment
// later), until the bar goes and the page jumps up. Liquid Glass is on for iOS 26 unless the app
// opts out in its Info.plist, so this is every build of Spotify on iOS 26, with or without the mod.
//
// So the bar is taken away at the start of the transition instead: the same call Spotify's own
// completion block makes, made 534ms earlier, while the page is still coming in. Animated, so that
// UIKit takes the bar out over the transition the way the alpha used to and the page has its own
// height from the first frame. Compensating the page instead — handing it those 54pt back as a
// negative additionalSafeAreaInsets — is what this hook did first, and it did nothing at all: the
// page's safe area reads 62 with the bar up, so the 54pt reach the page through Spotify's own
// layout guide (SessionContainerServiceImpl.provideMainContentLayoutGuide, whose observers are told
// through layoutGuideChanged), not through UIKit's safe area, and there is nothing to compensate.
//
// The cost is that the page being left behind is measured against the bar too, and reflows by the
// same 54pt as it slides away under the swipe. It is on its way off screen, which is the better
// place for the jump than the page being arrived at. A cancelled swipe puts the bar back on its
// own: Spotify's completion block sees the cancellation and asks for the state again, which for the
// page that stayed is a bar shown.
//
// Tree (trees/test5.txt): UILayoutContainerView holds UINavigationTransitionView and, beside it,
// SPNavigationBar {{0, 62}, {402, 54}} at alpha 0, gone from the tree altogether once the page has
// settled (trees/test6.txt).
#import "Core/SGCore.h"

// SPNavigationController's own states: 0 shows the bar, 1 gives it the page's own alpha, 2 hides it.
static const NSInteger kBarStateHidden = 2;

// SPTNavigationControllerNavigationBarState, which every page on the stack answers.
@interface UIViewController (SGNavigationBarState)
- (NSInteger)preferredNavigationBarState;
- (BOOL)prefersLiquidGlassNavigationBar;
@end

// The two questions SPNavigationController itself asks the page before it hides the bar: a page
// that asks for the glass bar is given one, however hidden it says it wants the bar to be.
static BOOL wantsNoBar(UIViewController *page) {
    if (![page respondsToSelector:@selector(preferredNavigationBarState)]) return NO;
    if (page.preferredNavigationBarState != kBarStateHidden) return NO;
    return !([page respondsToSelector:@selector(prefersLiquidGlassNavigationBar)] && page.prefersLiquidGlassNavigationBar);
}

%hook SPNavigationController

- (void)navigationController:(UINavigationController *)controller willShowViewController:(UIViewController *)page animated:(BOOL)animated {
    %orig;
    UINavigationController *nav = (UINavigationController *)self;
    if (nav.navigationBarHidden || !wantsNoBar(page)) return;
    SGLog(@"page transition: %@ wants no bar, taking it now rather than at the end", NSStringFromClass(page.class));
    [nav setNavigationBarHidden:YES animated:animated];
}

%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPNavigationController"]);
}
