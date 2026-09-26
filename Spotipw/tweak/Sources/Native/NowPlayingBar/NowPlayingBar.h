// The native look's now playing bar: Spotify's own bar with its device button hidden on request
// (NowPlayingBar.x), and the bar's flags (NowPlayingBarSettings.m).
#import <UIKit/UIKit.h>

#define SGHideBarConnect @"spotifyglass.hide.barConnect"   // the device button in the now playing bar

UIViewController *SGNowPlayingBarSettingsPage(void);
