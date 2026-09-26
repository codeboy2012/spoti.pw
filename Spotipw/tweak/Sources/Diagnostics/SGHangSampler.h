// FLEX builds: what the main thread is doing while it is stuck. While a watch is running, a background
// thread pings the main queue every 10 ms; once a ping has waited `kThreshold` (120 ms) the main thread
// is suspended for an instant, its stack walked by frame pointers, resumed, and the frames logged as
// "hang <reason> <n>/<m>" with the image and symbol of each, or the address in Spotify's own binary for
// scripts to symbolicate against its symbol table. A long stall is sampled again every 80 ms, up to 12
// samples a stall.
//
// Threading: start and stop on the main thread. Watches nest; the sampler runs while any is open.
#import <Foundation/Foundation.h>

// Runs the sampler until the matching stop, or for `seconds` when that is above 0 (no stop then).
void SGHangSamplerStart(NSString *reason, NSTimeInterval seconds);
void SGHangSamplerStop(void);
