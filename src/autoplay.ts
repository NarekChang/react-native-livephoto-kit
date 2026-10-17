import type { LivePhotoPlaybackStyle, LivePhotoViewProps } from './types';

export function toNativeAutoplay(
  autoplay: LivePhotoViewProps['autoplay']
): 'off' | LivePhotoPlaybackStyle {
  if (autoplay === true) return 'hint';
  return autoplay || 'off';
}
