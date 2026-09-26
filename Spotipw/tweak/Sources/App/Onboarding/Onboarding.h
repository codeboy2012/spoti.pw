// Onboarding: a welcome page over Home the first time this build runs, in glass: a pick between
// the redesign (offered first) and Spotify's own look, and a line on holding Home for Mod Settings.
// The look is picked at launch, so a changed pick ends the welcome in a restart. The Mod page
// offers it again.
#import <UIKit/UIKit.h>

#define SGKeyOnboardingSeen @"spotifyglass.onboarding.seen"

// Presents the tour over the top of the app; does nothing while it is already up.
void SGShowOnboarding(void);
BOOL SGOnboardingShowing(void);
