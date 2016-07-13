#import "XKFFmpegPlayer.h"

#import "KxMovieDecoder.h"
#import "KxAudioManager.h"

#define MIN_BUFFERED_DURATION       2.0
#define MAX_BUFFERED_DURATION       4.0

@interface XKFFmpegPlayer ()

@property (weak, nonatomic) id<XKFFmpegPlayerDelegate> delegate;

@property (nonatomic) KxMovieDecoder *decoder;
@property (nonatomic) dispatch_queue_t dispatchQueue;

@property (nonatomic) BOOL decoding;
@property (nonatomic) BOOL interrupted;

@property (nonatomic) NSMutableArray *videoFrames;
@property (nonatomic) CGFloat moviePosition;

@property (nonatomic) NSMutableArray *audioFrames;
@property (nonatomic) NSData *currentAudioFrame;
@property (nonatomic) NSUInteger currentAudioFramePos;

@property (nonatomic) CGFloat bufferedDuration;
@property (nonatomic) BOOL buffered;

@property (nonatomic) NSTimeInterval tickCorrectionTime;
@property (nonatomic) NSTimeInterval tickCorrectionPosition;
@property (nonatomic) NSUInteger tickCounter;

@end

@implementation XKFFmpegPlayer

- (void)load:(NSString *)path
    delegate:(id<XKFFmpegPlayerDelegate>)delegate
{
    self.delegate = delegate;
    
    self.paused = YES;
    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];
    
    self.decoder = [[KxMovieDecoder alloc] init];
    
    self.videoFrames = [NSMutableArray array];
    self.audioFrames = [NSMutableArray array];
    
    __weak typeof(self) welf = self;
    
    self.decoder.interruptCallback = ^BOOL() {
        if (welf)
            return welf.interrupted;
        
        return YES;
    };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [welf.decoder openFile:path
                         error:&error];
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (!error)
            {
                welf.dispatchQueue = dispatch_queue_create("com.appeloper.channels", DISPATCH_QUEUE_SERIAL);
                [welf.decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
                [welf play];
            }
            else if (self.delegate)
                [self.delegate failed:error];
        });
    });
}

- (void)play
{
    if (!self.paused)
        return;
    
    if (!(self.decoder.validVideo && self.decoder.validAudio))
        return;
    
    if (self.interrupted)
        return;
    
    self.paused = NO;
    self.interrupted = NO;
    self.tickCorrectionTime = 0;
    self.tickCounter = 0;
    
    [self asyncDecodeFrames];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^{
        [self tick];
    });
    
    if (self.decoder.validAudio)
        [self mute:NO];
    
    if (self.delegate) {
        [self.delegate playing];
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }
}

- (void)pause
{
    if (self.paused)
        return;
    
    self.paused = YES;
    [self mute:YES];
    
    if (self.delegate) {
        [self.delegate paused];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
    }
}

- (void)stop
{
    [self pause];
    self.interrupted = YES;
    [self freeBufferedFrames];
    
    if (self.dispatchQueue)
        self.dispatchQueue = nil;
}

- (void)mute:(BOOL)onOff
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    
    if (!onOff && self.decoder.validAudio)
    {
        audioManager.outputBlock = ^(float *data, UInt32 numFrames, UInt32 numChannels) {
            [self audioCallbackFillData:data
                              numFrames:numFrames
                            numChannels:(int)numChannels];
        };
        
        [audioManager play];
    }
    else
    {
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

- (void)seek:(float)position
{
    BOOL paused = self.paused;
    [self pause];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^{
        [self updatePosition:position * self.decoder.duration
                      paused:paused];
    });
}

#pragma mark - Internal

- (void)asyncDecodeFrames
{
    if (self.decoding)
        return;
    
    __weak typeof(self) welf = self;
    
    CGFloat duration = 0.0;
    
    self.decoding = YES;
    dispatch_async(self.dispatchQueue, ^{
        if (welf.paused)
            return;
        
        BOOL good = YES;
        while (good)
        {
            good = NO;
            @autoreleasepool
            {
                if (welf && welf.decoder && (welf.decoder.validVideo || welf.decoder.validAudio))
                {
                    NSArray *frames = [welf.decoder decodeFrames:duration];
                    if (frames.count)
                        if (welf)
                            good = [welf addFrames:frames];
                }
            }
        }
        
        if (welf)
            welf.decoding = NO;
    });
}

- (BOOL)addFrames:(NSArray *)frames
{
    if (self.decoder.validVideo)
    {
        @synchronized(self.videoFrames)
        {
            for (KxMovieFrame *frame in frames)
            {
                if (frame.type == KxMovieFrameTypeVideo)
                {
                    [self.videoFrames addObject:frame];
                    self.bufferedDuration += frame.duration;
                }
            }
        }
    }
    
    if (self.decoder.validAudio)
    {
        @synchronized(self.audioFrames)
        {
            for (KxMovieFrame *frame in frames)
            {
                if (frame.type == KxMovieFrameTypeAudio)
                {
                    [self.audioFrames addObject:frame];
                    if (!self.decoder.validVideo)
                        self.bufferedDuration += frame.duration;
                }
            }
        }
    }
    
    return !self.paused && self.bufferedDuration < MAX_BUFFERED_DURATION;
}

- (void)tick
{
    if (self.buffered && ((self.bufferedDuration > MIN_BUFFERED_DURATION) || self.decoder.isEOF))
    {
        self.tickCorrectionTime = 0;
        self.buffered = NO;
        if (self.delegate)
        {
            if (self.paused) {
                [self.delegate paused];
                [UIApplication sharedApplication].idleTimerDisabled = NO;
            }
            else {
                [self.delegate playing];
                [UIApplication sharedApplication].idleTimerDisabled = YES;
            }
        }
    }
    
    CGFloat interval = 0;
    if (!self.buffered)
        interval = [self presentFrame];
    
    if (!self.paused)
    {
        NSUInteger leftFrames = (self.decoder.validVideo ? self.videoFrames.count : 0) + (self.decoder.validAudio ? self.audioFrames.count : 0);
        
        if (leftFrames == 0)
        {
            if (self.decoder.isEOF)
            {
                [self pause];
                if (self.delegate)
                    [self.delegate tick:self.moviePosition - self.decoder.startTime
                               duration:self.decoder.duration];
                return;
            }
            
            if (MIN_BUFFERED_DURATION > 0 && !self.buffered)
            {
                self.buffered = YES;
                if (self.delegate)
                    [self.delegate loading];
            }
        }

        if (!leftFrames || !(self.bufferedDuration > MIN_BUFFERED_DURATION))
            [self asyncDecodeFrames];
        
        NSTimeInterval correction = [self tickCorrection];
        NSTimeInterval time = MAX(interval + correction, 0.01);
        
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^{
            [self tick];
        });
    }
    
    if (self.delegate)
        [self.delegate tick:self.moviePosition - self.decoder.startTime
                   duration:self.decoder.duration];
}

- (CGFloat)tickCorrection
{
    if (self.buffered)
        return 0;
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!self.tickCorrectionTime)
    {
        self.tickCorrectionTime = now;
        self.tickCorrectionPosition = self.moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = self.moviePosition - self.tickCorrectionPosition;
    NSTimeInterval dTime = now - self.tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    if (correction > 1.0 || correction < -1.0)
    {
        correction = 0;
        self.tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat)presentFrame
{
    CGFloat interval = 0;
    
    if (self.decoder.validVideo)
    {
        KxVideoFrame *frame;
        
        @synchronized(self.videoFrames)
        {
            if (self.videoFrames.count > 0)
            {
                frame = self.videoFrames[0];
                [self.videoFrames removeObjectAtIndex:0];
                self.bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
    }
    
    return interval;
}

- (CGFloat)presentVideoFrame:(KxVideoFrame *)frame
{
    KxVideoFrameRGB *rgbFrame = (KxVideoFrameRGB *)frame;
    
    if (self.delegate) {
        UIImage *image = nil;
        
        @try {
            image = [rgbFrame asImage];
        } @catch (NSException *exception) {
            image = nil;
        }
        
        [self.delegate presentFrame:image];
    }
    
    self.moviePosition = frame.position;
    
    return frame.duration;
}

- (void)audioCallbackFillData:(float *)outData
                    numFrames:(int)numFrames
                  numChannels:(int)numChannels
{
    if (self.buffered)
    {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    @autoreleasepool
    {
        while (numFrames > 0)
        {
            if (!self.currentAudioFrame)
            {
                @synchronized(self.audioFrames)
                {
                    NSUInteger count = self.audioFrames.count;
                    
                    if (count > 0)
                    {
                        KxAudioFrame *frame = self.audioFrames[0];
                        
                        if (self.decoder.validVideo)
                        {
                            CGFloat delta = self.moviePosition - frame.position;
                            
                            if (delta < -2.0)
                            {
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
                                break;
                            }
                            
                            [self.audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 2.0 && count > 1)
                                continue;
                        }
                        else
                        {
                            [self.audioFrames removeObjectAtIndex:0];
                            self.moviePosition = frame.position;
                            self.bufferedDuration -= frame.duration;
                        }
                        
                        self.currentAudioFramePos = 0;
                        self.currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (self.currentAudioFrame)
            {
                void *bytes = (Byte *)self.currentAudioFrame.bytes + self.currentAudioFramePos;
                NSUInteger bytesLeft = (self.currentAudioFrame.length - self.currentAudioFramePos);
                NSUInteger frameSizeOf = numChannels * sizeof(float);
                NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    self.currentAudioFramePos += bytesToCopy;
                else
                    self.currentAudioFrame = nil;
            }
            else
            {
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                break;
            }
        }
    }
}

- (void)updatePosition:(CGFloat)position
                paused:(BOOL)paused
{
    [self freeBufferedFrames];
    
    position = MIN(self.decoder.duration - 1, MAX(0, position));
    
    __weak typeof(self) welf = self;
    
    dispatch_async(self.dispatchQueue, ^{
        if (!welf)
            return;
        
        welf.decoder.position = position;
        
        if (!paused)
        {
            [welf decodeFrames];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (welf)
                {
                    welf.moviePosition = welf.decoder.position;
                    [welf presentFrame];
                    if (self.delegate)
                        [self.delegate tick:self.moviePosition - self.decoder.startTime
                                   duration:self.decoder.duration];
                    [welf play];
                }
            });
        }
        else
        {
            [welf decodeFrames];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (welf)
                {
                    welf.moviePosition = welf.decoder.position;
                    [welf presentFrame];
                    if (self.delegate)
                        [self.delegate tick:self.moviePosition - self.decoder.startTime
                                   duration:self.decoder.duration];
                }
            });
        }        
    });
}

- (void)freeBufferedFrames
{
    @synchronized(self.videoFrames)
    {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(self.audioFrames)
    {
        [self.audioFrames removeAllObjects];
        self.currentAudioFrame = nil;
    }
    
    self.bufferedDuration = 0;
}

- (BOOL)decodeFrames
{
    NSArray *frames = nil;
    
    if (self.decoder.validVideo || self.decoder.validAudio)
        frames = [self.decoder decodeFrames:0];
    
    if (frames.count)
        return [self addFrames:frames];
    
    return NO;
}

@end

@implementation XKFFmpegPlayerView

@end
