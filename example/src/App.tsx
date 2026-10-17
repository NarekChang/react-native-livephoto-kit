import { useRef, useState } from 'react';
import {
  Alert,
  Button,
  Image,
  SafeAreaView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  clearLivePhotoCache,
  LivePhotoError,
  LivePhotoView,
  pickLivePhoto,
  saveLivePhotoToLibrary,
  useGenerateLivePhoto,
  type LivePhotoFiles,
  type LivePhotoViewRef,
} from 'react-native-livephoto';

const describe = (error: unknown) =>
  error instanceof LivePhotoError
    ? `${error.code}: ${error.message}`
    : String(error);

// Served by Metro over http in development and bundled as a file in release builds;
// the library accepts both.
const sampleVideoUri =
  Image.resolveAssetSource(require('./assets/sample.mov'))?.uri ?? '';

export default function App() {
  const livePhotoRef = useRef<LivePhotoViewRef>(null);
  const [files, setFiles] = useState<LivePhotoFiles>();
  const [message, setMessage] = useState(
    'Generate a Live Photo from a video or pick one from your library'
  );
  const generation = useGenerateLivePhoto();

  const generate = async () => {
    const result = await generation.generate({
      videoUri: sampleVideoUri,
      maxDuration: 2,
    });
    if (result) {
      setFiles(result);
      setMessage('Generated. Long-press the photo to play it.');
    }
  };

  const pick = async () => {
    try {
      const picked = await pickLivePhoto();
      if (picked) {
        generation.reset();
        setFiles(picked);
        setMessage('Picked. Long-press the photo to play it.');
      }
    } catch (error) {
      setMessage(describe(error));
    }
  };

  const save = async () => {
    if (!files) return;
    try {
      const { assetId } = await saveLivePhotoToLibrary(files);
      Alert.alert('Saved to Photos', assetId);
    } catch (error) {
      Alert.alert('Error', describe(error));
    }
  };

  const clearCache = async () => {
    setFiles(undefined);
    generation.reset();
    await clearLivePhotoCache();
    setMessage('Cache cleared');
  };

  const status =
    generation.status === 'generating'
      ? `Generating… ${Math.round(generation.progress * 100)}%`
      : generation.status === 'error'
        ? describe(generation.error)
        : message;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.preview}>
        {files && (
          <LivePhotoView
            ref={livePhotoRef}
            source={files}
            autoplay
            showsBadge
            style={StyleSheet.absoluteFill}
            onLoad={({ width, height }) =>
              setMessage(`Loaded ${width}×${height}. Long-press to play.`)
            }
            onError={(error) => setMessage(describe(error))}
          />
        )}
      </View>
      <Text style={styles.status}>{status}</Text>
      <View style={styles.buttons}>
        {generation.status === 'generating' ? (
          <Button title="Cancel" onPress={generation.cancel} />
        ) : (
          <Button title="Generate" onPress={generate} />
        )}
        <Button title="Pick from library" onPress={pick} />
        <Button
          title="Play"
          disabled={!files}
          onPress={() => livePhotoRef.current?.play()}
        />
        <Button
          title="Stop"
          disabled={!files}
          onPress={() => livePhotoRef.current?.stop()}
        />
        <Button title="Save to Photos" disabled={!files} onPress={save} />
        <Button title="Clear cache" onPress={clearCache} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  preview: {
    flex: 1,
    margin: 16,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#eee',
  },
  status: {
    marginHorizontal: 16,
    textAlign: 'center',
  },
  buttons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    padding: 16,
  },
});
