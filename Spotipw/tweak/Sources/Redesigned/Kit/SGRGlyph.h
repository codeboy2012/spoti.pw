// Bare glyphs: an SF Symbol drawn over or instead of one of Spotify's own glyphs (the player's previous,
// play and next), and a glyph button of the Kit's own where Spotify has no control (the lyrics glyph in
// the player's footer). No glass: these sit in rows of controls, where a pane each would turn the row
// into glass sampling glass.
//
// Ownership: whoever adds them. Threading: main thread only.
#import <UIKit/UIKit.h>

// Takes no touches and is hidden from accessibility, so the Spotify control under it keeps both; put
// inside that control, it follows the control's own alpha when disabled or highlighted.
@interface SGRGlyphView : UIImageView
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight;
@property (nonatomic, readonly) NSString *symbol;
// A swap replaces the glyph with the symbol transition on iOS 17 (none under Reduce Motion); the same
// symbol again is a no-op.
- (void)setSymbol:(NSString *)symbol animated:(BOOL)animated;
@end

// A glyph that is a button: at least 44pt to touch whatever the glyph's size, dims and springs back
// when pressed, 0.35 alpha and "dimmed" to VoiceOver when disabled, and shows the large content
// viewer with its title when held at accessibility text sizes.
@interface SGRGlyphButton : UIControl
+ (instancetype)buttonWithSymbol:(NSString *)symbol pointSize:(CGFloat)size title:(NSString *)accessibilityTitle;
@property (nonatomic, readonly) SGRGlyphView *glyph;
@property (nonatomic, copy) void (^onTap)(void);
@end
