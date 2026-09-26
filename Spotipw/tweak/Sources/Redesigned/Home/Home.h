// The Home redesign: Spotify's Home page kept, with its controllers, lists and cards, decluttered to a
// music app on black and restyled from the Kit. No settings of its own.
//
//     HomeSections.x   an allow list of the feed's sections: the shortcuts grid, the DJ and the shelves of
//                      cards stay; video and episode previews, episode cards and any new kind collapse. The
//                      DJ loses its heading, and the flags the redesign forces on Home
//     HomeHeader.x     a large title where the filter pills were, the avatar at the trailing edge, no scrim
//     HomeHeadings.x   the shelves' headings in the Music app's size, drawn over Spotify's
//     HomeCards.x      the Encore button every card is: shortcut tiles (HomeTiles.m), continuous corners on the
//                      shelf covers, the DJ card at the card radius without its talking transcript
//     HomeTiles.m      a shortcut tile's picture run across the tile, blurred behind its title
//     HomePerf.x       FLEX builds: the frames of each scroll of Home and the time the hooks above took
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Whether HomeSections.x has collapsed the section in this cell.
BOOL SGRHomeSectionCollapsed(UIView *cell);

// Styles a shortcut tile (id=Shortcut.Card.Home) and keeps its picture in step with its cover (HomeTiles.m).
void SGRHomeStyleTile(UIView *tile);

// FLEX builds only (HomePerf.x): a hook takes the time as it starts and hands it back as it ends; outside
// a FLEX build Begin returns 0 and End does nothing.
typedef NS_ENUM(NSUInteger, SGRHomeProbe) {
    SGRHomeProbeSections,
    SGRHomeProbeHeader,
    SGRHomeProbeHeadings,
    SGRHomeProbeCards,
    SGRHomeProbeTiles,
    SGRHomeProbeCount,
};
CFTimeInterval SGRHomeProbeBegin(void);
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began);
