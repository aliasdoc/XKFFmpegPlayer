#import <UIKit/UIKit.h>

@protocol XKFFmpegPlayerDelegate;

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

@interface XKFFmpegPlayerView : UIImageView

@property (nonatomic) XKFFmpegPlayer *player;

@end

@protocol XKFFmpegPlayerDelegate <NSObject>

- (void)loading;
- (void)failed:(NSError *)error;

- (void)playing;
- (void)paused;

- (void)tick:(float)position
    duration:(float)duration;

- (void)presentFrame:(UIImage *)image;

@end