// Album redesign: everything under the track list dropped but what the album itself says.
//
// Spotify closes an album page with a run of sections the server sends -- more by the artist, related music
// videos, concerts, merch, you might also like -- and more of them whenever it likes. None of them is the
// album. So the rule is not a list of their names, which would be a list in one language that the next
// section walks past: every one of those cells reports no height, and only two are kept.
//
// Tree (trees/clean/album/04.txt:979-2576). Everything under the tracks comes as an Element_List cell whose
// content is an ElementContentView over Album_PageImpl.FooterStructuredData -- the headings, the carousels,
// the merch cards, the 16pt spacers between them, and the two worth keeping:
//
//     Album.ConsumptionExperience   "22 songs • 1hr 24min", the line the Music app puts under a track list
//     Album.Copyright               the © and ℗ lines, which are the label's and stay
//
// The tracks themselves are the same cell class over RetrievalListStructuredData and are never touched here.
//
// A dropped cell is 0 tall, but what it holds keeps the height it measured at, hidden and cut off by the
// cell: Spotify's content squeezed to 0 with the cell breaks its own required constraints on every layout
// pass, which is what held the main thread where dropped sections scrolled in on Home (2026-09-17). The two
// kept cells are given the gap the spacers used to draw and their content is pinned under it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

// Over the album's own line, and between it and the copyright: the spacers they sat between are gone.
static const CGFloat kLead = 16;

static char kSettledKey;

static BOOL isFooterContent(UIView *content) {
    static NSMutableDictionary<id, NSNumber *> *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    if (!cls) return NO;
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"Album_PageImpl20FooterStructuredData"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

// The two the album says about itself, restyled as it is kept: Spotify draws both in white, and under a
// track list they are a footnote, not a line to read.
static BOOL isKept(UIView *content) {
    UIView *kept = nil;
    for (NSString *identifier in @[@"Album.ConsumptionExperience", @"Album.Copyright"]) {
        kept = kept ?: SGRFindByIdentifier(content, identifier, NULL);
    }
    if (!kept) return NO;
    SGForEachView(kept, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRTertiary()]) label.textColor = SGRTertiary();
    });
    return YES;
}

// The content laid at `lead` down the cell, at the height it measured at, and the cell sized for both.
// Kept on the cell so its own passes, which size the content to the cell again, do not undo it.
static void settle(UICollectionViewCell *cell, CGFloat natural, CGFloat lead) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, @[@(natural), @(lead)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, lead, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    BOOL dropped = lead == 0;
    if (content.hidden != dropped) content.hidden = dropped;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = dropped;
}

static void unsettle(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign album: %@", what);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView.subviews.firstObject;
    // Cells are reused across kinds, and one settled before can hold a track row now.
    if (!isFooterContent(content) || !SGRAlbumPageOf(cell)) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) unsettle(cell);
        return %orig;
    }
    UICollectionViewLayoutAttributes *result = %orig;
    CGFloat natural = MAX(1, result.size.height);
    if (isKept(content)) {
        settle(cell, natural, kLead);
        result.size = CGSizeMake(result.size.width, natural + kLead);
        logOnce(@"the album's own line and its copyright kept under the tracks");
    } else {
        settle(cell, natural, 0);
        result.size = CGSizeMake(result.size.width, 0);
        logOnce(@"the sections under the tracks dropped");
    }
    return result;
}

// The cell's own passes size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    NSArray<NSNumber *> *settled = objc_getAssociatedObject(self, &kSettledKey);
    if (settled) settle((UICollectionViewCell *)self, settled[0].doubleValue, settled[1].doubleValue);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) unsettle((UICollectionViewCell *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
