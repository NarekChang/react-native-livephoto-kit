import type * as React from 'react';
import {
  codegenNativeCommands,
  codegenNativeComponent,
  type CodegenTypes,
  type HostComponent,
  type ViewProps,
} from 'react-native';

type LoadEvent = Readonly<{
  width: CodegenTypes.Double;
  height: CodegenTypes.Double;
}>;

type ErrorEvent = Readonly<{
  code: string;
  message: string;
}>;

type PlaybackEvent = Readonly<{
  style: string;
}>;

export interface NativeProps extends ViewProps {
  // A pair of local or remote files, or a Photos library asset identifier.
  source?: Readonly<{
    photoUri?: string;
    videoUri?: string;
    assetId?: string;
  }>;
  autoplay?: CodegenTypes.WithDefault<'off' | 'hint' | 'full', 'off'>;
  muted?: CodegenTypes.WithDefault<boolean, false>;
  resizeMode?: CodegenTypes.WithDefault<'cover' | 'contain', 'cover'>;
  // URI of an image shown until the Live Photo is loaded.
  placeholder?: string;
  showsBadge?: CodegenTypes.WithDefault<boolean, false>;
  gestureEnabled?: CodegenTypes.WithDefault<boolean, true>;
  onLoad?: CodegenTypes.DirectEventHandler<LoadEvent>;
  onError?: CodegenTypes.DirectEventHandler<ErrorEvent>;
  onPlaybackStart?: CodegenTypes.DirectEventHandler<PlaybackEvent>;
  onPlaybackEnd?: CodegenTypes.DirectEventHandler<PlaybackEvent>;
}

type ComponentType = HostComponent<NativeProps>;

// React.ElementRef (not ComponentRef): codegen accepts ComponentRef only since RN 0.84.
interface NativeCommands {
  play: (viewRef: React.ElementRef<ComponentType>, style: string) => void;
  stop: (viewRef: React.ElementRef<ComponentType>) => void;
}

export const Commands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ['play', 'stop'],
});

export default codegenNativeComponent<NativeProps>('LivePhotoView');
