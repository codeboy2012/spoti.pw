// Album: parts of the album page hidden one switch each, and the cover behind its header (Album.x).
// An unset switch is off.
#import <UIKit/UIKit.h>

#define SGKeyAlbumBackdrop @"spotifyglass.albumBackdrop"

#define SGHideAlbumExplore @"spotifyglass.hide.albumExplore"
#define SGHideAlbumAddTo @"spotifyglass.hide.albumAddTo"
#define SGHideAlbumDownload @"spotifyglass.hide.albumDownload"
#define SGHideAlbumMore @"spotifyglass.hide.albumMore"

#define SGHideAlbumMoreBy @"spotifyglass.hide.albumMoreBy"
#define SGHideAlbumVideos @"spotifyglass.hide.albumVideos"
#define SGHideAlbumConcerts @"spotifyglass.hide.albumConcerts"
#define SGHideAlbumMerch @"spotifyglass.hide.albumMerch"
#define SGHideAlbumYouMightLike @"spotifyglass.hide.albumYouMightLike"

UIViewController *SGAlbumSettingsPage(void);   // opened from the Home & Library page
