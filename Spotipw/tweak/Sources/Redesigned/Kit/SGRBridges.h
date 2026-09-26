// What the redesigned screens read from Spotify and ask of it, through one hook each, so no screen
// hooks the player a second time.
//
// Player state is Shared/Player/PlayerState.h's, imported here so a redesigned screen needs one header.
//
// Artwork is keyed on the picture the playing track names, not on the track or on where it was read
// (issue #58). The track's metadata carries its cover's image id (image_xlarge_url and its smaller
// sizes, spotify:image:<16 digits of size><24 digits of the picture>, out/karaoke-diag.log:174); two
// tracks of one album share it. On a change of picture the Kit fetches that picture itself, from
// i.scdn.co where Spotify's images live, and the answer is published whenever it lands, however late,
// unless the track has moved on to another picture meanwhile. Until it lands, and when it cannot
// (offline), the covers on screen stand in: the now playing bar's 40pt cover (trees/clean/artist/01.txt:
// id=SPTNowPlayingBar > Encore.ImageView > UIImageView 40x40), read after the bar's layout and a few
// times after a track change, and the player's own cover, which PlayerField.x publishes. A view read
// can be the last track's picture still -- a cell of the covers list that has not reloaded, a bar whose
// new picture is still loading -- so every picture published is remembered, weakly, with the picture it
// was published as, and a view showing one of them for another picture is not believed.
//
// Threading: everything here is main thread only; the player's reports are moved onto it.
#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"

#pragma mark - now playing artwork

typedef NS_ENUM(NSInteger, SGRArtworkQuality) {
    SGRArtworkQualityLow,     // the now playing bar's 40pt cover
    SGRArtworkQualityHigh,    // the player's own cover
    SGRArtworkQualityExact,   // the picture the track's metadata names, fetched by the Kit
};
// Posted when the artwork changes, object nil, userInfo image, trackURI and quality.
extern NSNotificationName const SGRNowPlayingArtworkDidChangeNotification;
// A picture read off a screen for `trackURI`: ignored unless that track is still the one playing, when
// it is a picture already published for another track, when a better one is in for this picture, and
// when it is the same image again.
void SGRSetNowPlayingArtwork(UIImage *image, NSString *trackURI, SGRArtworkQuality quality);
// The last artwork published; `trackURI` and `identity` (for -[SGRArtworkField setArtwork:identity:
// animated:]: the same identity is the same picture) are filled when asked for. Until the playing
// track's own picture is in, this is the last one.
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity);

#pragma mark - the player's open and close

// While the full screen player opens or closes (Shared/Player/PlayerEvents.x announces it).
BOOL SGRPlayerIsTransitioning(void);
// SGPlayerTransitionNotification and SGPlayerTransitionEndedNotification as blocks, for as long as
// `owner` lives. The blocks are handed the owner so they need not capture it.
void SGRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner));
