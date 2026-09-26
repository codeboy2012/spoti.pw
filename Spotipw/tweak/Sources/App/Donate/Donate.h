// Donate: Ko-fi, asked for from the Mod Settings row, a sheet after the first welcome tour (after its
// restart when the look changed), then two days on and every fourteen after that.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

extern NSString *const SGKofiURL;
UIColor *SGKofiColor(void);

// A glass capsule with a Ko-fi rim circling it and a breathing glow. Prominent tints the glass itself.
@interface SGKofiButton : UIControl
- (instancetype)initWithTitle:(NSString *)title prominent:(BOOL)prominent;
@end

void SGShowDonateSheet(void);
SGModRow *SGDonateRow(void);
void SGWatchForDonate(void);
// A tour is done: the sheet follows it, or follows Home after the restart.
void SGDonateAfterTour(BOOL restarting);
BOOL SGDonateAfterTourPending(void);
void SGOfferDonate(void);
