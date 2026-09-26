// The Updates page and the launch notice on the simulator, with the real check running against the
// repo's GitHub Releases. The build it claims to be is SG_VERSION, set by build.sh, so `0.18.0`
// shows a version behind the newest and `99.0.0` shows one that is current. `wipe` clears what an
// earlier run stored, so it starts as a phone that has never checked does; `notice` puts a plain
// screen up and runs SGWatchForUpdates() over it, the way the settings %ctor does inside Spotify;
// `recheck` taps Check now five seconds in.
#import <UIKit/UIKit.h>
#import "App/About/About.h"

// Spotify's welcome tour is not built here, and nothing holds the screen against the notice.
BOOL SGOnboardingShowing(void) {
    return NO;
}

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation Delegate

// What the notice comes up over: a stand-in for whatever Spotify has on screen when it opens.
static UIViewController *plainScreen(void) {
    UIViewController *screen = [UIViewController new];
    screen.view.backgroundColor = UIColor.blackColor;
    UILabel *label = [UILabel new];
    label.text = @"Spotify";
    label.textColor = [UIColor colorWithWhite:1 alpha:0.35];
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [screen.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:screen.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:screen.view.centerYAnchor],
    ]];
    return screen;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"wipe"]) {
        for (NSString *key in @[@"spotifyglass.update.checked", @"spotifyglass.update.releases", @"spotifyglass.update.told"])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    }
    BOOL notice = [arguments containsObject:@"notice"];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UINavigationController *stack = [[UINavigationController alloc] initWithRootViewController:notice ? plainScreen() : SGUpdatePage()];
    stack.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = stack;
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    if (notice) SGWatchForUpdates();
    if ([arguments containsObject:@"recheck"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGCheckForUpdate(YES);
        });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
