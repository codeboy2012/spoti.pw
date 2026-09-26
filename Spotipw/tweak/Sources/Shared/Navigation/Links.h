// Opening a spotify: URI the way the app opens a link of its own, through its link dispatcher: the
// tabs of the mod's own on either look's bar, the redesigned player's lyrics glyph.
#import <Foundation/Foundation.h>

// NO before the dispatcher is set up, or for a nil URI.
BOOL SGOpenSpotifyURI(NSURL *uri);
id SGLinkDispatcher(void);   // SPTLinkDispatcherImplementation, nil until it is set up

// Whether the dispatcher has somewhere to send a URI, asked the way it asks itself before it opens
// one: every handler in its URI subtype registry is asked -URISubtypeHandlerCanHandleURI:, then the
// same again for the URI its fallback resolver remaps an unhandled one to. None of them saying yes is
// what ends in Spotify's "Couldn't open link" alert.
typedef NS_ENUM(NSInteger, SGLinkRoute) {
    SGLinkRouteUnknown = -1,   // the dispatcher or its registry is not there to ask
    SGLinkRouteNone = 0,
    SGLinkRouteOpens = 1,
};
// `via`, when given, is the class of the handler that said yes, prefixed "remap <uri> " when it took
// the fallback resolver's URI; nil otherwise.
SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via);

// What someone typed or pasted as a link, as a spotify: URI: surrounding blanks trimmed, and a share
// link (https://open.spotify.com/[intl-xx/]playlist/<id>?si=…) turned into spotify:playlist:<id>.
// nil when there is nothing a URI can be made of.
NSURL *SGSpotifyURIFromText(NSString *text);
