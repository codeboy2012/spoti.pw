// Home declutter: sections of Home collapsed and the filter pills hidden, one switch each on the Home &
// Library page. A section is an Element_List cell; a hidden one reports zero height when the list sizes
// it, so the list closes up around it.
//
// Trees (trees/home*.txt): every section is a CollectionViewCell whose content view names the page
// (Home_EvoPageImpl) and whose subtree names the section.
#import "Core/SGCore.h"
#import "Home.h"

static const struct { __unsafe_unretained NSString *marker, *key; } sections[] = {
    {@"Home_AnchorsAndShortcutsKit", SGHideHomeShortcuts},
    {@"Discovery_PromoElement", SGHideHomePromo},
    {@"Discovery_PreviewElement", SGHideHomePreviews},
    {@"Discovery_DJElement", SGHideHomeDJ},
};

// Class names of everything in the cell. Lists nested in the cell are laid out first so the
// cells that name the section (shortcut tiles) exist.
static NSString *classNamesIn(UIView *cell) {
    NSMutableString *names = [NSMutableString string];
    SGForEachView(cell, ^(UIView *v) {
        if (v != cell && [v isKindOfClass:UICollectionView.class]) [v layoutIfNeeded];
        [names appendString:NSStringFromClass(v.class)];
        [names appendString:@"\n"];
    });
    return names;
}

static NSString *hiddenKeyFor(UICollectionViewCell *cell) {
    // A cell inside another section's list: the outer section decides.
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return nil;
    }
    NSString *names = nil;
    for (size_t i = 0; i < sizeof(sections) / sizeof(sections[0]); i++) {
        if (!SGHidden(sections[i].key)) continue;
        if (!names) names = classNamesIn(cell);
        if ([names containsString:@"Home_EvoPageImpl"] && [names containsString:sections[i].marker]) return sections[i].key;
    }
    return nil;
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    NSString *key = hiddenKeyFor((UICollectionViewCell *)self);
    if (!key) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"home: collapsed the first section, %@", key); });
    return result;
}
%end

%hook _TtC14Home_PillUIKit14PillScrollView
- (void)didMoveToWindow {
    %orig;
    if (SGHidden(SGHideHomePills)) ((UIView *)self).hidden = YES;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC14Home_PillUIKit14PillScrollView",
    ]);
}
