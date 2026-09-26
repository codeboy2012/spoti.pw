// The karaoke view goes over the lyrics part of the full screen lyrics page (trees/lyrics.txt:
// Lyrics_FullscreenElementPageImpl.LyricsView, between the header and the controls), so Spotify's
// header, close button and controls stay working. It is laid over rather than swapped in: Spotify's
// list keeps running underneath and comes back the moment a track has no synced lyrics.
#import "Core/SGCore.h"
#import "SGRKaraokeView.h"

static char kKaraokeKey;

%hook _TtC32Lyrics_FullscreenElementPageImpl10LyricsView
- (void)layoutSubviews {
    %orig;
    UIView *host = (UIView *)self;
    SGRKaraokeView *view = objc_getAssociatedObject(host, &kKaraokeKey);
    if (!view) {
        SGLog(@"karaoke: page opened, playing %@", SGKaraokePlayingTrack());
        view = [[SGRKaraokeView alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, &kKaraokeKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (view.superview == host) [host bringSubviewToFront:view];
    else [host addSubview:view];
    view.frame = host.bounds;
    [view syncSiblings];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl10LyricsView"]);
}
