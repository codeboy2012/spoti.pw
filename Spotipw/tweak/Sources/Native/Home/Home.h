// Home: the gradient behind the top of the page (HomeGradient.x), off until it is asked for, and
// the settings that shape it (HomeGradientChoices.m, the Gradient page in HomeSettings.m).
#import <UIKit/UIKit.h>

#define SGKeyHomeGradient @"spotifyglass.homeGradient"

// Parts of Home to hide, one switch each (HomeDeclutter.x). An unset switch is off.
#define SGHideHomeShortcuts @"spotifyglass.hide.homeShortcuts"
#define SGHideHomePills @"spotifyglass.hide.homePills"
#define SGHideHomePromo @"spotifyglass.hide.homePromo"
#define SGHideHomePreviews @"spotifyglass.hide.homePreviews"
#define SGHideHomeDJ @"spotifyglass.hide.homeDJ"

// Every setting the gradient is shaped by. One entry per setting in HomeGradientChoices.m holds the
// names the Gradient page offers, the key it is stored under and the one it falls back to, so a
// name and what it does cannot drift apart.
typedef NS_ENUM(NSInteger, SGHomeChoice) {
    SGHomeChoiceTint,       // which colour it fades
    SGHomeChoiceStrength,   // how far up or down that colour is taken
    SGHomeChoiceHeight,     // how far down the page it reaches
    SGHomeChoiceCount,
};

NSArray<NSString *> *SGHomeChoiceNames(SGHomeChoice choice);
NSString *SGHomeChoiceKey(SGHomeChoice choice);
NSInteger SGHomeChoiceDefault(SGHomeChoice choice);
// The index set for `choice`: its own default while nothing is set, or while what is set is a name
// this build no longer offers.
NSInteger SGHomeChoiceValue(SGHomeChoice choice);

UIViewController *SGHomeSettingsPage(void);
UIViewController *SGHomeGradientPage(void);
