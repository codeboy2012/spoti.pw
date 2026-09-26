// Spotify's own newer design, which it ships behind several flags switched off: the glass navigation
// bar, the new player slider, the sheet style player, the queue and Connect sheets, the redesigned
// player header, the sleep timer's options sheet. The redesign is built on all of it, so while
// Redesigned UI is on each is forced and its row elsewhere shows it locked.
#import "Core/SGCore.h"
#import "SGRedesign.h"

%hook SPTHubViewController
- (BOOL)prefersLiquidGlassNavigationBar {
    return YES;
}
%end

%ctor {
    SGRedesignForceFlags(@"glass design", @{
        @"ios-reprise-liquid-glass-properties.context_menu_in_navigation_bar_enabled": @YES,
        @"ios-feature-encoreexperiments.new_npv_slider_enabled": @YES,
        @"ios-feature-nowplaying.sheet_style_npv": @YES,
        @"ios-feature-nowplaying.bottom_sheet_queue_enabled": @YES,
        @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled": @YES,
        @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet": @YES,
        @"ios-playbackcontrol-audiovideoswitcher-impl.enable_connect_bottom_sheet": @YES,
        @"ios-feature-sleeptimer.use_options_sheet": @YES,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTHubViewController"]);
}
