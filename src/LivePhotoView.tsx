import type { Ref } from 'react';
import { View } from 'react-native';
import type { LivePhotoViewProps, LivePhotoViewRef } from './types';

// Live Photos exist only on iOS; elsewhere the view renders as an empty container.
export function LivePhotoView({
  ref: _ref,
  source: _source,
  autoplay: _autoplay,
  muted: _muted,
  resizeMode: _resizeMode,
  placeholder: _placeholder,
  showsBadge: _showsBadge,
  gestureEnabled: _gestureEnabled,
  onLoad: _onLoad,
  onError: _onError,
  onPlaybackStart: _onPlaybackStart,
  onPlaybackEnd: _onPlaybackEnd,
  ...viewProps
}: LivePhotoViewProps & { ref?: Ref<LivePhotoViewRef> }) {
  return <View {...viewProps} />;
}
