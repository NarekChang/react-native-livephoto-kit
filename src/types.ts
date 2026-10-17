import type {
  ImageRequireSource,
  ImageURISource,
  ViewProps,
} from 'react-native';
import type { LivePhotoError } from './errors';

export type LivePhotoSource =
  /** A photo + video pair: `file://`, absolute paths and `http(s)://` URIs are supported. */
  | { photoUri: string; videoUri: string }
  /** A `PHAsset.localIdentifier` of a Live Photo in the user's library (needs read access). */
  | { assetId: string };

export type LivePhotoPlaybackStyle = 'hint' | 'full';

export type LivePhotoViewProps = ViewProps & {
  source?: LivePhotoSource;
  /**
   * Play once the Live Photo is loaded: `'hint'` (a short preview), `'full'`,
   * or `true` for `'hint'`. Default `false`.
   */
  autoplay?: boolean | LivePhotoPlaybackStyle;
  /** Default `false`. */
  muted?: boolean;
  /** Default `'cover'`. */
  resizeMode?: 'cover' | 'contain';
  /** Image shown until the Live Photo is loaded: `require('./photo.jpg')` or `{ uri }`. */
  placeholder?: ImageRequireSource | ImageURISource;
  /** Show the system "LIVE" badge in the top-left corner. Default `false`. */
  showsBadge?: boolean;
  /** Play when the user long-presses the view. Default `true`. */
  gestureEnabled?: boolean;
  /** The Live Photo is ready; size in pixels. */
  onLoad?: (event: { width: number; height: number }) => void;
  onError?: (error: LivePhotoError) => void;
  onPlaybackStart?: (event: { style: LivePhotoPlaybackStyle }) => void;
  onPlaybackEnd?: (event: { style: LivePhotoPlaybackStyle }) => void;
};

export type LivePhotoViewRef = {
  /** Default style is `'full'`. */
  play: (style?: LivePhotoPlaybackStyle) => void;
  stop: () => void;
};

export type GenerateLivePhotoOptions = {
  /** Source video: `file://`, absolute path or `http(s)://`. */
  videoUri: string;
  /** Key photo. When omitted, the frame at `keyPhotoTime` is extracted from the video. */
  photoUri?: string;
  /** Key photo position in seconds. Default: the middle of the video. */
  keyPhotoTime?: number;
  /**
   * Maximum length of the Live Photo video in seconds. Longer videos are trimmed to a
   * window around the key photo. Live Photos taken by the Camera app are about 3 seconds.
   */
  maxDuration?: number;
  /** Called with values from 0 to 1 while the video is written. */
  onProgress?: (progress: number) => void;
  /** Aborting it stops the generation; the promise rejects with `E_CANCELLED`. */
  signal?: AbortSignal;
};

export type LivePhotoFiles = {
  /** `file://` URI of the generated JPEG. */
  photoUri: string;
  /** `file://` URI of the generated QuickTime movie. */
  videoUri: string;
};

export type SavedLivePhoto = {
  /** `PHAsset.localIdentifier` of the new asset. */
  assetId: string;
};

export type PickedLivePhoto = LivePhotoFiles & {
  /** `PHAsset.localIdentifier` of the picked photo, when the system provides it. */
  assetId?: string;
};

export type PhotoLibraryAccessLevel = 'addOnly' | 'readWrite';

export type PhotoLibraryPermissionStatus =
  'notDetermined' | 'restricted' | 'denied' | 'authorized' | 'limited';

export type LivePhotoErrorCode =
  /** A URI is neither a file path, `file://` nor `http(s)://`. */
  | 'E_INVALID_URI'
  /** Bad options or unusable media (no video track, unreadable photo, incomplete source). */
  | 'E_INVALID_INPUT'
  | 'E_DOWNLOAD'
  | 'E_WRITE'
  /** Photo library access was denied. */
  | 'E_PERMISSION'
  | 'E_ASSET_NOT_FOUND'
  /** `<LivePhotoView>` couldn't load the source, e.g. files that are not a matching pair. */
  | 'E_LOAD'
  /** Called on a platform other than iOS. */
  | 'E_UNSUPPORTED'
  /** The generation was cancelled with an `AbortSignal`. */
  | 'E_CANCELLED'
  | 'E_UNKNOWN';
