// The object the player's own controls drive: the seek amounts are named in seconds by the
// selectors themselves, so a gesture needs no unit of its own.
#import <Foundation/Foundation.h>

@interface SPTNowPlayingPlaybackControllerImplementation : NSObject
- (void)seekForwardBySeconds:(double)seconds;
- (void)seekBackwardBySeconds:(double)seconds;
- (void)skipToNextWhileDragging:(BOOL)dragging;
- (void)skipToPreviousWhileDragging:(BOOL)dragging;
- (void)setPaused:(BOOL)paused;
- (void)setGlobalShuffleMode:(BOOL)shuffling;
- (void)toggleRepeatMode;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;
@property (nonatomic, readonly, getter=isShuffling) BOOL shuffling;
@property (nonatomic, readonly) BOOL seekingAllowed;
@property (nonatomic, readonly) BOOL canSkipNext;
@property (nonatomic, readonly) BOOL disallowPausing;
@property (nonatomic, readonly) BOOL disallowResuming;
@end
