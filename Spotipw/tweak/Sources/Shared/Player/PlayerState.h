// What Spotify's player is doing, read through one hook so no feature of the mod hooks the player a
// second time, and under either look: the state is data, not a screen.
//
// -[_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation player:stateDidChange:]
// (objc-methods.txt:60654) is the now playing platform's own player observer, and until that has
// reported, an observer of the mod's added to the first SPTEsperantoPlayer the app adds one to
// (-[SPTEsperantoPlayer addPlayerObserver:], :35729).
//
// Threading: the player reports from several threads and everything here is moved onto the main one,
// so observers are called there.
#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"

// A URI Spotify types as id (NSURL or NSString) as a string; nil for anything else.
NSString *SGURIString(id uri);

@protocol SGPlayerStateObserver <NSObject>
// Called when the track, the context, paused, playing, loading or shuffle changed, not for position.
- (void)playerStateDidChange:(SPTPlayerState *)state;
@end
// Observers are held weakly and need no removal.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer);
// The last state reported, nil before the player has reported one.
SPTPlayerState *SGPlayerState(void);
