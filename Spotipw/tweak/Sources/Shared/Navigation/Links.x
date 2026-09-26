// The dispatcher is a singleton the app builds at startup; -setMainUILoaded: is the last call of its
// setup (objc-methods.txt:38809).
#import "Core/SGCore.h"
#import "Headers/SPTLinkDispatcherImplementation.h"
#import "Links.h"
#import <objc/message.h>

static __weak SPTLinkDispatcherImplementation *sg_linkDispatcher;

id SGLinkDispatcher(void) {
    return sg_linkDispatcher;
}

BOOL SGOpenSpotifyURI(NSURL *uri) {
    SPTLinkDispatcherImplementation *dispatcher = sg_linkDispatcher;
    if (!uri || ![dispatcher respondsToSelector:@selector(navigateToURI:options:interactionID:)]) return NO;
    [dispatcher navigateToURI:uri options:0 interactionID:nil];
    return YES;
}

#pragma mark - asking before opening

// The chain a spotify: link takes in 9.1.78, read off the binary: -[SPTLinkDispatcherImplementation
// navigateToURI:…] hands it to the URI scheme dispatcher, whose "spotify" handler is the dispatcher's
// -spotifyLinkHandler (SPTSpotifyLinkHandler). That one passes the cleaned URI to its
// -URISubtypeRegistry (SPTURISubtypeRegistryImplementation), which keeps the handlers of its -handlers
// hash table that answer -URISubtypeHandlerCanHandleURI: YES and opens with the first by priority;
// pages go through Navigation's PageResolverURISubtypeHandler. With no taker, -handleSpotifyURL:
// tries again once with -remapURI: (its fallback resolver's URI), and only then shows the alert.
static id sg_send(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

static id sg_send1(id target, NSString *selector, id arg) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
}

// The class of the first handler that takes `uri`, nil for none. A handler whose name says it only
// listens (Jam's SGSNavigationURIHandledEventSource) is not asked, so a question is not taken for a
// navigation.
static NSString *takerFor(id<NSFastEnumeration> handlers, NSURL *uri, NSUInteger *asked) {
    SEL canHandle = NSSelectorFromString(@"URISubtypeHandlerCanHandleURI:");
    for (id handler in handlers) {
        NSString *name = NSStringFromClass([handler class]);
        if ([name containsString:@"EventSource"] || ![handler respondsToSelector:canHandle]) continue;
        (*asked)++;
        if (((BOOL (*)(id, SEL, id))objc_msgSend)(handler, canHandle, uri)) return name;
    }
    return nil;
}

SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via) {
    if (via) *via = nil;
    if (!uri) return SGLinkRouteNone;
    id linkHandler = sg_send(sg_linkDispatcher, @"spotifyLinkHandler");
    id handlers = sg_send(sg_send(linkHandler, @"URISubtypeRegistry"), @"handlers");
    if (![handlers conformsToProtocol:@protocol(NSFastEnumeration)]) return SGLinkRouteUnknown;
    @try {
        NSURL *clean = sg_send(uri, @"spt_normalizedSpotifyURI");
        if (![clean isKindOfClass:NSURL.class]) clean = uri;
        NSUInteger asked = 0;
        NSString *taker = takerFor(handlers, clean, &asked);
        if (!taker) {
            NSURL *remapped = sg_send1(linkHandler, @"remapURI:", clean);
            if ([remapped isKindOfClass:NSURL.class] && ![remapped isEqual:clean]) {
                taker = takerFor(handlers, remapped, &asked);
                if (taker) taker = [NSString stringWithFormat:@"remap %@ %@", remapped.absoluteString, taker];
            }
        }
        if (!asked) return SGLinkRouteUnknown;
        if (via) *via = taker;
        return taker ? SGLinkRouteOpens : SGLinkRouteNone;
    } @catch (NSException *e) {
        SGLog(@"links: asking about %@ threw %@", uri, e.reason);
        return SGLinkRouteUnknown;
    }
}

NSURL *SGSpotifyURIFromText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:trimmed];
    NSString *host = parts.host.lowercaseString;
    if ([parts.scheme.lowercaseString hasPrefix:@"http"] && [host isEqualToString:@"open.spotify.com"]) {
        NSMutableArray<NSString *> *path = [NSMutableArray array];
        for (NSString *piece in [parts.path componentsSeparatedByString:@"/"]) {
            if (piece.length) [path addObject:piece];
        }
        if (path.count && [path.firstObject hasPrefix:@"intl-"]) [path removeObjectAtIndex:0];
        if (path.count >= 2) return [NSURL URLWithString:[@"spotify:" stringByAppendingString:[path componentsJoinedByString:@":"]]];
    }
    return [NSURL URLWithString:trimmed];
}

%hook SPTLinkDispatcherImplementation
- (void)setMainUILoaded:(BOOL)loaded {
    %orig;
    sg_linkDispatcher = (SPTLinkDispatcherImplementation *)self;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTLinkDispatcherImplementation"]);
}
