// The playlist redesign: Spotify's playlist page kept, with its controllers, its header and its list, and
// laid out the way the Music app lays a playlist out. Liked Songs and a playlist of the user's own are the
// same page (trees/clean/liked-songs/01.txt, own-playlist/01.txt: one FTPViewController, one
// SPTFreeTierPlaylistEncoreHeaderViewController), so one redesign covers all three. Album and artist pages
// are built by another framework and are left alone.
//
//     PlaylistField.x   the artwork field behind the whole page, the artwork it is read from, the flags
//                       the screen forces
//     PlaylistHeader.x  the header: the cover full bleed at the top dissolving into the field, the title,
//                       the creator and the length centred under it, and one row of glass controls --
//                       shuffle, a prominent Play capsule, add, and more where Spotify still has it
//     PlaylistRows.x    the track rows on the field with no surface of their own, rounded artwork, a
//                       hairline between them, and the curation pills collapsed
//     PlaylistMenu.x    Sort and Mix, the two of the curation pills the ⋯ menu does not already offer,
//                       put on that menu's own sheet
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// The page's list (trees/clean/playlist/02.txt:23).
extern NSString *const SGRPlaylistListIdentifier;
// PlaylistMenu.x. The row of curation pills over the first track (own-playlist/01.txt:33).
extern NSString *const SGRPlaylistCurationIdentifier;
// The page keeps the curation row the cell `cell` is laying out, so the ⋯ sheet has Spotify's own Sort and
// Mix buttons to fire once the list has scrolled past them. Does nothing for any other cell.
void SGRPlaylistTakeCuration(UIView *cell);
// And keeps Spotify's own Sort button from the header's find-on-page toolbar, which sorts the same list
// and, unlike the pill, is in the header rather than in a cell the list reuses.
void SGRPlaylistTakeSort(UIView *page, UIView *button);

// The playlist page `view` is on, or nil: SPTFreeTierPlaylistEncoreHeaderViewController's own view, the one
// the tree names PL.Header, for anything under the header, and FTPViewController's view for the list.
UIViewController *SGRPlaylistHeaderOf(UIView *view);
// The page `view` is on -- FTPViewController's own view, the one the field and the pinned ⋯ belong to --
// or nil when it is on no playlist page.
UIView *SGRPlaylistPageOf(UIView *view);

// PlaylistField.x. The field belongs to the page `view` is on, found by walking up from it, so two playlist
// pages on the navigation stack keep a field each.
//
// The colour the page's field is showing, SGRNeutralField() before one has been read: what the header's
// cover has to dissolve into for there to be no seam.
UIColor *SGRPlaylistFieldColor(UIView *view);
// The cover of the page `view` is on, for its field to take its colour from. The same image again is a no-op.
void SGRPlaylistSetArtwork(UIView *view, UIImage *image);
