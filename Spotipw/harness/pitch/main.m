// Runs SGTimePitch.m on the Mac both ways the tweak runs it: in place over IO buffers of Spotify's sizes
// (pitch alone), and pulling a source at a rate (speed, with or without pitch). Checks a sine comes out
// at the pitch asked for and the source is consumed at the rate asked for, reports the unit's pulls,
// underruns, delay and cost, and writes a song shifted up and down to listen to.
//
//     ./build.sh && build/pitch [song]
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import "Shared/Player/SGTimePitch.h"

static const double kRate = 44100;

// Frequency by the zero crossings of the steady part.
static double frequency(const float *samples, size_t count) {
    size_t first = 0, last = 0, crossings = 0;
    for (size_t i = 1; i < count; i++) {
        if (samples[i - 1] < 0 && samples[i] >= 0) {
            if (!crossings) first = i;
            last = i;
            crossings++;
        }
    }
    return crossings > 1 ? (crossings - 1) * kRate / (last - first) : 0;
}

// The frame where the output first gets loud: the delay the shifter adds.
static size_t onset(const float *samples, size_t count) {
    for (size_t i = 0; i < count; i++) if (fabsf(samples[i]) > 0.1f) return i;
    return count;
}

static UInt32 bufferSize(size_t index, int pattern) {
    if (pattern == 0) return 1024;
    if (pattern == 1) return 4096;
    static const UInt32 odd[] = {470, 471, 512, 1024, 256, 941};
    return odd[index % 6];
}

static void runSine(float semitones, int pattern) {
    size_t total = (size_t)(kRate * 3);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t i = 0; i < total; i++) left[i] = right[i] = 0.5f * sinf(2 * M_PI * 440 * i / kRate);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    if (!shifter) {
        printf("no shifter\n");
        exit(1);
    }
    SGTimePitchSetSemitones(shifter, semitones);
    SGTimePitchReset(shifter);
    uint64_t start = mach_absolute_time();
    size_t done = 0, index = 0;
    while (done < total) {
        UInt32 frames = (UInt32)MIN((size_t)bufferSize(index++, pattern), total - done);
        float *channels[2] = {left + done, right + done};
        if (!SGTimePitchProcess(shifter, channels, frames)) printf("  process failed at %zu\n", done);
        done += frames;
    }
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    double seconds = (mach_absolute_time() - start) * (double)timebase.numer / timebase.denom / 1e9;
    double expected = 440 * pow(2, semitones / 12);
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    printf("sine %+5.1f st, buffers %-8s: %6.1f Hz (want %6.1f, %+.2f%%), delay %4zu frames (unit %.1f ms), largest pull %u, underruns %u, failures %u, cost %.2f%% of real time\n",
           semitones, pattern == 0 ? "1024" : pattern == 1 ? "4096" : "mixed", measured, expected, (measured / expected - 1) * 100,
           onset(left, total), SGTimePitchLatency(shifter) * 1000, SGTimePitchLargestPull(shifter),
           SGTimePitchUnderruns(shifter), SGTimePitchFailures(shifter), seconds / 3 * 100);
    free(left);
    free(right);
}

static void runSong(NSString *path, float semitones, NSString *outPath) {
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) {
        printf("cannot open %s\n", path.UTF8String);
        return;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32,
    };
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    ExtAudioFileRef output;
    AudioStreamBasicDescription wav = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 16,
    };
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outPath], kAudioFileWAVEType, &wav, NULL, kAudioFileFlags_EraseFile, &output);
    ExtAudioFileSetProperty(output, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    SGTimePitchSetSemitones(shifter, semitones);
    float left[1024], right[1024];
    size_t seconds = 0;
    for (;;) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
        UInt32 frames = 1024;
        if (ExtAudioFileRead(file, &frames, &buffers.list) || !frames) break;
        float *channels[2] = {left, right};
        SGTimePitchProcess(shifter, channels, frames);
        buffers.list.mBuffers[0].mDataByteSize = buffers.second.mDataByteSize = frames * 4;
        ExtAudioFileWrite(output, frames, &buffers.list);
        seconds += frames;
        if (seconds > kRate * 40) break;
    }
    ExtAudioFileDispose(file);
    ExtAudioFileDispose(output);
    printf("wrote %s (%+.0f st), underruns %u\n", outPath.UTF8String, semitones, SGTimePitchUnderruns(shifter));
}

typedef struct { double phase; } Sine;

static OSStatus sineSource(void *context, UInt32 frames, AudioBufferList *data) {
    Sine *sine = context;
    for (UInt32 i = 0; i < frames; i++) {
        float value = 0.5f * sinf(2 * M_PI * 440 * (sine->phase + i) / kRate);
        for (UInt32 c = 0; c < data->mNumberBuffers; c++) ((float *)data->mBuffers[c].mData)[i] = value;
    }
    sine->phase += frames;
    return noErr;
}

static void runPull(float rate, float semitones) {
    Sine sine = {0};
    SGTimePitch *unit = SGTimePitchCreate(kRate, 2, sineSource, &sine);
    SGTimePitchSetRate(unit, rate);
    SGTimePitchSetSemitones(unit, semitones);
    size_t total = (size_t)(kRate * 4);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t done = 0; done < total; done += 1024) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, 4096, left + done}}}, {1, 4096, right + done}};
        if (SGTimePitchRender(unit, 1024, &buffers.list) != noErr) printf("  render failed\n");
    }
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    double expected = 440 * pow(2, semitones / 12);
    double consumedRate = (double)SGTimePitchConsumed(unit) / total;
    printf("pull rate %.2f %+3.0f st: %6.1f Hz (want %6.1f, %+.2f%%), consumed %.3fx, largest pull %u, failures %u\n", rate, semitones,
           measured, expected, (measured / expected - 1) * 100, consumedRate, SGTimePitchLargestPull(unit), SGTimePitchFailures(unit));
    free(left);
    free(right);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        for (int pattern = 0; pattern < 3; pattern++) {
            for (NSNumber *semitones in @[@-12, @-5, @-1, @0.5, @3, @7, @12]) runSine(semitones.floatValue, pattern);
        }
        for (NSNumber *rate in @[@0.5, @0.75, @1, @1.25, @1.5, @2]) {
            runPull(rate.floatValue, 0);
            runPull(rate.floatValue, 3);
        }
        if (argc > 1) {
            NSString *song = @(argv[1]);
            runSong(song, 3, @"build/song+3.wav");
            runSong(song, -4, @"build/song-4.wav");
        }
    }
    return 0;
}
