# react-native-livephoto-kit

[![npm version](https://img.shields.io/npm/v/react-native-livephoto-kit.svg)](https://www.npmjs.com/package/react-native-livephoto-kit)
[![npm downloads](https://img.shields.io/npm/dm/react-native-livephoto-kit.svg)](https://www.npmjs.com/package/react-native-livephoto-kit)
[![platform: iOS](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](#requirements)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Show, create and save Apple [Live Photos](https://support.apple.com/en-us/104966) in React Native. iOS only.

```tsx
import { LivePhotoView, generateLivePhoto } from 'react-native-livephoto-kit';

const livePhoto = await generateLivePhoto({ videoUri, maxDuration: 3 });

<LivePhotoView
  source={livePhoto}
  autoplay
  style={{ width: 300, height: 400 }}
/>;
```

What's included:

- `<LivePhotoView>` wraps `PHLivePhotoView`. It plays on long-press, like in the Photos app.
- `generateLivePhoto()` turns any video into a Live Photo, with progress and cancellation. The video isn't re-encoded, so it's fast and keeps its quality.
- `pickLivePhoto()` opens the system picker limited to Live Photos.
- `saveLivePhotoToLibrary()` saves the result to Photos.

If you find it useful, a ⭐ on GitHub helps others find it. Issues and PRs are welcome.

## Requirements

- React Native 0.80 or newer with the New Architecture (on by default since 0.76)
- iOS 15.1 or newer

On Android and web, `<LivePhotoView>` renders an empty `View` and the functions reject with `E_UNSUPPORTED`, so shared code still runs.

## Installation

```sh
npm install react-native-livephoto-kit
cd ios && bundle exec pod install
```

Add the permission descriptions you need to `Info.plist`:

```xml
<!-- saveLivePhotoToLibrary() -->
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Saves Live Photos to your library.</string>

<!-- only for <LivePhotoView source={{ assetId }} /> -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Shows Live Photos from your library.</string>
```

Generating and picking Live Photos don't need any permissions. The system picker runs outside your app.

### Expo

Expo Go doesn't support custom native code, so use a [development build](https://docs.expo.dev/develop/development-builds/introduction/). Instead of editing `Info.plist`, add the config plugin:

```json
{
  "expo": {
    "plugins": ["react-native-livephoto-kit"]
  }
}
```

The plugin adds `NSPhotoLibraryAddUsageDescription`. It accepts two options:

```json
[
  "react-native-livephoto-kit",
  {
    "savePhotosPermission": "Save your Live Photos to the library.",
    "photosPermission": "Show Live Photos from your library."
  }
]
```

- `savePhotosPermission` sets the text of `NSPhotoLibraryAddUsageDescription`. Pass `false` to leave it out.
- `photosPermission` adds `NSPhotoLibraryUsageDescription`. It isn't added unless you set it.

## Usage

A screen that turns a video into a Live Photo and saves it:

```tsx
import { Button, Text, View } from 'react-native';
import {
  LivePhotoView,
  saveLivePhotoToLibrary,
  useGenerateLivePhoto,
} from 'react-native-livephoto-kit';

export function LivePhotoMaker({ videoUri }: { videoUri: string }) {
  const { generate, cancel, status, progress, result, error } =
    useGenerateLivePhoto();

  return (
    <View style={{ flex: 1 }}>
      {result && (
        <LivePhotoView
          source={result}
          autoplay
          showsBadge
          style={{ flex: 1 }}
        />
      )}

      {status === 'generating' && (
        <>
          <Text>{Math.round(progress * 100)}%</Text>
          <Button title="Cancel" onPress={cancel} />
        </>
      )}
      {status === 'error' && <Text>{error?.message}</Text>}

      <Button
        title="Create"
        onPress={() => generate({ videoUri, maxDuration: 3 })}
      />
      <Button
        title="Save"
        disabled={!result}
        onPress={() => result && saveLivePhotoToLibrary(result)}
      />
    </View>
  );
}
```

Showing a Live Photo the user picks:

```tsx
const picked = await pickLivePhoto(); // null if the user cancels
if (picked) setSource(picked);
```

URIs can be `file://`, absolute paths or `http(s)://`. Remote files are downloaded once and cached by URL.

## API

### `<LivePhotoView>`

Takes all [`View` props](https://reactnative.dev/docs/view#props), plus:

| Prop              | Type                                                              | Default   |                                                                                                  |
| ----------------- | ----------------------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------ |
| `source`          | `{ photoUri: string; videoUri: string }` \| `{ assetId: string }` |           | A photo and video pair, or the `localIdentifier` of a Live Photo in the library.                 |
| `autoplay`        | `boolean` \| `'hint'` \| `'full'`                                 | `false`   | Play once loaded. `'hint'` is the short preview, `'full'` the whole clip. `true` means `'hint'`. |
| `muted`           | `boolean`                                                         | `false`   |                                                                                                  |
| `resizeMode`      | `'cover'` \| `'contain'`                                          | `'cover'` |                                                                                                  |
| `placeholder`     | `require('./cover.jpg')` \| `{ uri: string }`                     |           | Shown until the Live Photo is loaded.                                                            |
| `showsBadge`      | `boolean`                                                         | `false`   | The "LIVE" badge in the top-left corner.                                                         |
| `gestureEnabled`  | `boolean`                                                         | `true`    | Play on long-press. Turn it off where long-press already does something else, e.g. in a list.    |
| `onLoad`          | `({ width, height }) => void`                                     |           | Size in pixels.                                                                                  |
| `onError`         | `(error: LivePhotoError) => void`                                 |           | For example `E_LOAD` if the photo and video aren't a matching pair.                              |
| `onPlaybackStart` | `({ style }) => void`                                             |           |                                                                                                  |
| `onPlaybackEnd`   | `({ style }) => void`                                             |           | Also called when playback is stopped.                                                            |

`style` accepts any `View` style. Like `<Image>`, the view clips its content, so `borderRadius` rounds the photo too. Because of that clipping, iOS doesn't draw a shadow on the view itself. To get a shadow, wrap the view in a `View` that has the shadow, or pass `overflow: 'visible'` if you don't need rounded corners.

To size the view to the photo's proportions, use the size from `onLoad`:

```tsx
const [aspectRatio, setAspectRatio] = useState(3 / 4);

<LivePhotoView
  source={source}
  style={{ width: '100%', aspectRatio, borderRadius: 16 }}
  onLoad={({ width, height }) => setAspectRatio(width / height)}
/>;
```

Ref methods: `play(style = 'full')` and `stop()`.

```tsx
const ref = useRef<LivePhotoViewRef>(null);
<LivePhotoView ref={ref} source={source} />;
ref.current?.play();
```

### `generateLivePhoto(options): Promise<LivePhotoFiles>`

Creates a JPEG and a `.mov` in the app's Caches directory and resolves with `{ photoUri, videoUri }`. You can pass the result to `source` or `saveLivePhotoToLibrary()` as is.

| Option         | Type                         |                                                                                                  |
| -------------- | ---------------------------- | ------------------------------------------------------------------------------------------------ |
| `videoUri`     | `string`                     | Any video AVFoundation can read (`.mov`, `.mp4`, …).                                             |
| `photoUri`     | `string`                     | Key photo, the still shown before playback. Defaults to the video frame at `keyPhotoTime`.       |
| `keyPhotoTime` | `number`                     | Key photo position in seconds. Defaults to the middle of the video.                              |
| `maxDuration`  | `number`                     | Trims longer videos to this many seconds around the key photo. Camera Live Photos are about 3 s. |
| `onProgress`   | `(progress: number) => void` | 0 to 1.                                                                                          |
| `signal`       | `AbortSignal`                | Aborting stops the generation, deletes the partial files and rejects with `E_CANCELLED`.         |

```ts
const controller = new AbortController();
const files = await generateLivePhoto({
  videoUri,
  keyPhotoTime: 1.2,
  maxDuration: 3,
  onProgress: (p) => console.log(p),
  signal: controller.signal,
});
```

### `useGenerateLivePhoto()`

`generateLivePhoto` with its state in React:

```ts
const { generate, cancel, reset, status, progress, result, error } =
  useGenerateLivePhoto();
```

- `status` is one of `'idle' | 'generating' | 'success' | 'error'`.
- `generate(options)` takes the same options as `generateLivePhoto`, except `onProgress` and `signal`.
- `generate()` doesn't throw. It resolves with the files, or with `undefined` and sets `error`, so you can pass it to `onPress` directly.
- A new `generate()` call cancels the previous one. Unmounting the component cancels it too.
- `cancel()` stops a running generation and goes back to `idle`.
- `reset()` does the same and also clears `result` and `error`.

### `pickLivePhoto(): Promise<PickedLivePhoto | null>`

Opens the system photo picker limited to Live Photos. It copies the selected photo and video into the cache and resolves with `{ photoUri, videoUri, assetId? }`, or with `null` if the user cancels.

### `saveLivePhotoToLibrary(files): Promise<{ assetId: string }>`

Saves the pair to Photos as one Live Photo. Asks for add-only access if the app doesn't have it yet, and rejects with `E_PERMISSION` if the user says no.

### `requestPhotoLibraryPermission(accessLevel = 'addOnly')`

Resolves with `'notDetermined' | 'restricted' | 'denied' | 'authorized' | 'limited'`. `accessLevel` is `'addOnly'` or `'readWrite'`. Use it to ask before saving, for example during onboarding.

### `clearLivePhotoCache(): Promise<void>`

Deletes everything the library has generated, picked or downloaded. Previously returned URIs stop working, so save what you want to keep first. iOS may also clear the Caches directory when storage is low.

### Errors

When a promise rejects, the error is a `LivePhotoError` with a `code`. `onError` receives the same type.

```ts
try {
  await generateLivePhoto({ videoUri });
} catch (error) {
  if (error instanceof LivePhotoError && error.code === 'E_CANCELLED') return;
  throw error;
}
```

| Code                | When                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| `E_INVALID_URI`     | The URI isn't an absolute path, `file://` or `http(s)://`.                 |
| `E_INVALID_INPUT`   | No video track, unreadable photo, incomplete `source`, `maxDuration <= 0`. |
| `E_DOWNLOAD`        | A remote file couldn't be downloaded.                                      |
| `E_WRITE`           | The Live Photo files couldn't be written.                                  |
| `E_PERMISSION`      | Photo library access was denied.                                           |
| `E_ASSET_NOT_FOUND` | No asset with this `assetId`, or no read access to the library.            |
| `E_LOAD`            | `<LivePhotoView>` or `pickLivePhoto` couldn't load the Live Photo.         |
| `E_CANCELLED`       | The generation was cancelled.                                              |
| `E_UNSUPPORTED`     | Not running on iOS.                                                        |
| `E_UNKNOWN`         | Anything else, see `message`.                                              |

All types (`LivePhotoFiles`, `LivePhotoViewRef`, `GenerateLivePhotoOptions`, `LivePhotoErrorCode`, …) are exported from the package.

## How it works

A Live Photo is a JPEG or HEIC photo and a short QuickTime movie that share a content identifier. `generateLivePhoto` writes a new identifier into the photo's Apple maker note and into the movie's metadata. It also adds a `still-image-time` metadata track that marks which frame is the key photo. Photos uses the identifier to pair the two files.

The video and audio samples are copied as they are. `maxDuration` trims through an edit list rather than by re-encoding.

## Limitations

- Android has Motion Photos, a different format. This library doesn't support it.
- The legacy architecture (the old bridge) isn't supported.
- The generated photo is always a JPEG, even when `photoUri` is a HEIC.
- Remote files are cached by URL. If the file behind a URL changes, change the URL too (for example `?v=2`) or call `clearLivePhotoCache()`.

## Example app

[`example/`](example/) generates a Live Photo from a bundled clip, picks one from the library, plays it and saves it.

```sh
git clone https://github.com/NarekChang/react-native-livephoto-kit.git
cd react-native-livephoto-kit
npm install
npm run example ios
```

## Contributing

Bug reports and PRs are welcome. For a bug, include your React Native and iOS versions and, if you can, a minimal repro. The [contributing guide](CONTRIBUTING.md) covers the setup, tests and commit conventions.

## License

MIT
