import { LivePhotoError } from './errors';
import type {
  GenerateLivePhotoOptions,
  LivePhotoFiles,
  PhotoLibraryAccessLevel,
  PhotoLibraryPermissionStatus,
  PickedLivePhoto,
  SavedLivePhoto,
} from './types';

const unsupported = () =>
  Promise.reject(
    new LivePhotoError(
      'E_UNSUPPORTED',
      "'react-native-livephoto-kit' is only supported on iOS."
    )
  );

export function generateLivePhoto(
  _options: GenerateLivePhotoOptions
): Promise<LivePhotoFiles> {
  return unsupported();
}

export function saveLivePhotoToLibrary(
  _files: LivePhotoFiles
): Promise<SavedLivePhoto> {
  return unsupported();
}

export function requestPhotoLibraryPermission(
  _accessLevel?: PhotoLibraryAccessLevel
): Promise<PhotoLibraryPermissionStatus> {
  return unsupported();
}

export function pickLivePhoto(): Promise<PickedLivePhoto | null> {
  return unsupported();
}

export function clearLivePhotoCache(): Promise<void> {
  return unsupported();
}
