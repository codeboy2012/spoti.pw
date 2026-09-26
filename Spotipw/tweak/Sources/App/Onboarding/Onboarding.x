// The tour goes up the first time Home appears, not at launch: a fresh sideload lands on the login
// screen first, and a tour over that is wrong. A moment after, so Home has drawn under the glass.
// A tour that ended in a restart leaves the donate sheet for this Home instead.
#import "Core/SGCore.h"
#import "Onboarding.h"
#import "App/Donate/Donate.h"

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (SGFlag(SGKeyOnboardingSeen, NO)) SGOfferDonate();
            else SGShowOnboarding();
        });
    });
}
%end

%ctor {
    if (SGFlag(SGKeyOnboardingSeen, NO) && !SGDonateAfterTourPending()) return;
    %init;
    SGRequireClasses(@[@"_TtC19Home_FunkisPageImpl20FunkisViewController"]);
}
