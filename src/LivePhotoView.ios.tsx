import {
  useImperativeHandle,
  useRef,
  type ComponentRef,
  type Ref,
} from 'react';
import { Image, StyleSheet } from 'react-native';
import { toNativeAutoplay } from './autoplay';
import { toLivePhotoError } from './errors';
import NativeLivePhotoView, { Commands } from './LivePhotoViewNativeComponent';
import type {
  LivePhotoPlaybackStyle,
  LivePhotoViewProps,
  LivePhotoViewRef,
} from './types';

export function LivePhotoView({
  ref,
  autoplay,
  placeholder,
  onLoad,
  onError,
  onPlaybackStart,
  onPlaybackEnd,
  style,
  ...props
}: LivePhotoViewProps & { ref?: Ref<LivePhotoViewRef> }) {
  const nativeRef = useRef<ComponentRef<typeof NativeLivePhotoView>>(null);

  useImperativeHandle(ref, () => ({
    play: (playbackStyle = 'full') => {
      if (nativeRef.current) Commands.play(nativeRef.current, playbackStyle);
    },
    stop: () => {
      if (nativeRef.current) Commands.stop(nativeRef.current);
    },
  }));

  // Codegen types `style` as a plain string; native only ever sends 'hint' or 'full'.
  return (
    <NativeLivePhotoView
      ref={nativeRef}
      {...props}
      style={[styles.clip, style]}
      autoplay={toNativeAutoplay(autoplay)}
      placeholder={
        placeholder == null
          ? undefined
          : Image.resolveAssetSource(placeholder)?.uri
      }
      onLoad={onLoad && ((e) => onLoad(e.nativeEvent))}
      onError={onError && ((e) => onError(toLivePhotoError(e.nativeEvent)))}
      onPlaybackStart={
        onPlaybackStart &&
        ((e) =>
          onPlaybackStart({
            style: e.nativeEvent.style as LivePhotoPlaybackStyle,
          }))
      }
      onPlaybackEnd={
        onPlaybackEnd &&
        ((e) =>
          onPlaybackEnd({
            style: e.nativeEvent.style as LivePhotoPlaybackStyle,
          }))
      }
    />
  );
}

const styles = StyleSheet.create({
  // Like <Image>: borderRadius clips the photo without the user adding overflow: 'hidden'.
  clip: { overflow: 'hidden' },
});
