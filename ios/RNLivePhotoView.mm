#import "RNLivePhotoView.h"
#import "RNLivePhotoSwift.h"

#import <React/RCTConversions.h>

#import <react/renderer/components/RNLivePhotoSpec/ComponentDescriptors.h>
#import <react/renderer/components/RNLivePhotoSpec/EventEmitters.h>
#import <react/renderer/components/RNLivePhotoSpec/Props.h>
#import <react/renderer/components/RNLivePhotoSpec/RCTComponentViewHelpers.h>

using namespace facebook::react;

@interface RNLivePhotoView () <RCTLivePhotoViewViewProtocol>
@end

@implementation RNLivePhotoView {
  RNLivePhotoContentView *_livePhotoView;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<LivePhotoViewComponentDescriptor>();
}

// The content view holds loading state and in-flight requests, so recycling is not worth the reset logic.
+ (BOOL)shouldBeRecycled
{
  return NO;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const LivePhotoViewProps>();
    _props = defaultProps;

    _livePhotoView = [[RNLivePhotoContentView alloc] initWithFrame:frame];

    __weak RNLivePhotoView *weakSelf = self;
    _livePhotoView.onLoad = ^(CGSize size) {
      if (auto emitter = [weakSelf livePhotoEventEmitter]) {
        emitter->onLoad({.width = size.width, .height = size.height});
      }
    };
    _livePhotoView.onError = ^(NSString *code, NSString *message) {
      if (auto emitter = [weakSelf livePhotoEventEmitter]) {
        emitter->onError({.code = RCTStringFromNSString(code), .message = RCTStringFromNSString(message)});
      }
    };
    _livePhotoView.onPlaybackStart = ^(NSString *style) {
      if (auto emitter = [weakSelf livePhotoEventEmitter]) {
        emitter->onPlaybackStart({.style = RCTStringFromNSString(style)});
      }
    };
    _livePhotoView.onPlaybackEnd = ^(NSString *style) {
      if (auto emitter = [weakSelf livePhotoEventEmitter]) {
        emitter->onPlaybackEnd({.style = RCTStringFromNSString(style)});
      }
    };

    self.contentView = _livePhotoView;
  }

  return self;
}

- (std::shared_ptr<const LivePhotoViewEventEmitter>)livePhotoEventEmitter
{
  return std::static_pointer_cast<const LivePhotoViewEventEmitter>(_eventEmitter);
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<const LivePhotoViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const LivePhotoViewProps>(props);

  // Playback options go first so a source loaded in this update already sees them.
  if (oldViewProps.autoplay != newViewProps.autoplay) {
    _livePhotoView.autoplay = RCTNSStringFromString(toString(newViewProps.autoplay));
  }
  if (oldViewProps.muted != newViewProps.muted) {
    _livePhotoView.muted = newViewProps.muted;
  }
  if (oldViewProps.resizeMode != newViewProps.resizeMode) {
    _livePhotoView.resizeMode = RCTNSStringFromString(toString(newViewProps.resizeMode));
  }

  if (oldViewProps.placeholder != newViewProps.placeholder) {
    _livePhotoView.placeholder = RCTNSStringFromString(newViewProps.placeholder);
  }
  if (oldViewProps.showsBadge != newViewProps.showsBadge) {
    _livePhotoView.showsBadge = newViewProps.showsBadge;
  }
  if (oldViewProps.gestureEnabled != newViewProps.gestureEnabled) {
    _livePhotoView.gestureEnabled = newViewProps.gestureEnabled;
  }

  const auto &oldSource = oldViewProps.source;
  const auto &newSource = newViewProps.source;
  if (oldSource.photoUri != newSource.photoUri || oldSource.videoUri != newSource.videoUri ||
      oldSource.assetId != newSource.assetId) {
    [_livePhotoView setSourcePhotoUri:RCTNSStringFromString(newSource.photoUri)
                             videoUri:RCTNSStringFromString(newSource.videoUri)
                              assetId:RCTNSStringFromString(newSource.assetId)];
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTLivePhotoViewHandleCommand(self, commandName, args);
}

- (void)play:(NSString *)style
{
  [_livePhotoView play:style];
}

- (void)stop
{
  [_livePhotoView stop];
}

@end
