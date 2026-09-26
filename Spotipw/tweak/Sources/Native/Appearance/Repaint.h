// The areas the native look's tweaks stripped and Repaint.x keeps transparent when Spotify repaints
// them, each set by the tweak that owns it.
#import <UIKit/UIKit.h>

extern __weak UIView *sg_lyricsCardRoot;    // Native/Player/LyricsCard.x
extern __weak UIView *sg_lyricsPageRoot;    // Native/Lyrics/LyricsPage.x
extern __weak UIView *sg_homeRoot;          // Native/Home/HomeGradient.x, the base surface only
extern __weak UIView *sg_npvBackdropRoot;   // Native/Player/Player.x, the plane behind the player
