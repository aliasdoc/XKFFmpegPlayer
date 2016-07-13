# XKFFmpegPlayer
Clean [FFmpeg 3.0](https://github.com/xbydev/DDPlayer/tree/master/DDPlayer/DDPlayer/FFmpeg-iOS) player for iOS / tvOS.
Based on [kxmovie](https://github.com/kolyvan/kxmovie)

## Objects

### XKFFmpegPlayer

```Objective-C
@interface XKFFmpegPlayer : NSObject

@property (nonatomic) BOOL paused;

- (void)load:(NSString *)path
    delegate:(id<XKFFmpegPlayerDelegate>)delegate;

- (void)play;
- (void)pause;
- (void)stop;

- (void)mute:(BOOL)onOff;
- (void)seek:(float)position;

@end
```

### XKFFmpegPlayerView

```Objective-C
@interface XKFFmpegPlayerView : UIImageView

@property (nonatomic) XKFFmpegPlayer *player;

@end
```

### XKFFmpegPlayerDelegate

```Objective-C
@protocol XKFFmpegPlayerDelegate <NSObject>

- (void)loading;
- (void)failed:(NSError *)error;

- (void)playing;
- (void)paused;

- (void)tick:(float)position
    duration:(float)duration;

- (void)presentFrame:(UIImage *)image;

@end
```

## How to use

### Requirements

**Frameworks and Libs**
[FFmpeg Libs](https://github.com/xbydev/DDPlayer/tree/master/DDPlayer/DDPlayer/FFmpeg-iOS), VideoToolbox.framework, libz.tbd, libbz2.tbd, libiconv.tbd

**Buid Settings**

(Header Search Paths)
$(PROJECT_DIR)/{PATH}/FFmpegLibs/include

(Library Search Paths)
$(PROJECT_DIR)/{PATH}/FFmpegLibs/lib

### Code

```Objective-C
// Use as a normal view (UIImageView), with autolayout (or not)

// Interface builder
@property (nonatomic, weak) IBOutlet XKFFmpegPlayerView *playerView;

// Code (self.codePlayerView = [[XKFFmpegPlayerView alloc] initWithFrame:CGRectMake(0, 0, 320, 240)])
@property (nonatomic) XKFFmpegPlayerView *codePlayerView;
```

```Objective-C
// For play

- (void)playURL:(NSURL *)url {
    
    XKFFmpegPlayer *player = [[XKFFmpegPlayer alloc] init];
    
    [player load:url.absoluteString
        delegate:self];
    
    self.playerView.player = player;
}
```

```Objective-C
// Delegate, all methods required (but some can do nothing)

- (void)loading {
    // loading or start buffering
    
    // e.g. [self.activityIndicator startActivity];
}

- (void)failed:(NSError *)error {
    // when player failed to play url
    // e.g. show an error
}

- (void)playing {
    // end buffering and ready to play (or to take a snapshot)
    // player changed to play state
    
    // e.g. [self.activityIndicator stopActivity];
    // e.g. [self updatePlaybackControls:YES];
}

- (void)paused {
    // end buffering and ready to play (or to take a snapshot)
    // player changed to paused state
    
    // e.g. [self.activityIndicator stopActivity];
    // e.g. [self updatePlaybackControls:YES];
}

- (void)tick:(float)position
    duration:(float)duration {
    // player tick
    
    // e.g. self.timerLabel.text = [self formattedTimer:position duration:duration];
    // e.g. self.progressView.value = position / duration;
}

- (void)presentFrame:(UIImage *)image {
    // set image frame to UIImageView
    self.playerView.image = image;
}
```

