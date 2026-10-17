import { LivePhotoError, toLivePhotoError } from './errors';
import NativeLivePhoto from './NativeLivePhoto';
import type {
  GenerateLivePhotoOptions,
  LivePhotoFiles,
  PhotoLibraryAccessLevel,
  PhotoLibraryPermissionStatus,
  PickedLivePhoto,
  SavedLivePhoto,
} from './types';

async function call<T>(promise: Promise<T>): Promise<T> {
  try {
    return await promise;
  } catch (error) {
    throw toLivePhotoError(error);
  }
}

/**
 * Builds a Live Photo pair (JPEG + MOV sharing a content identifier) from a video
 * and an optional key photo. Files are written to the app's Caches directory.
 */
export async function generateLivePhoto({
  onProgress,
  signal,
  ...options
}: GenerateLivePhotoOptions): Promise<LivePhotoFiles> {
  if (!onProgress && !signal) {
    return call(NativeLivePhoto.generate(options));
  }
  if (signal?.aborted) {
    throw cancelled();
  }
  // The request id matches this call's progress events (shared by all calls) and lets it
  // be cancelled.
  const requestId = `generate-${++lastRequestId}`;
  const subscription =
    onProgress &&
    NativeLivePhoto.onGenerateProgress((event) => {
      if (event.requestId === requestId) onProgress(event.progress);
    });
  const abort = () => NativeLivePhoto.cancelGenerate(requestId);
  signal?.addEventListener('abort', abort);
  try {
    return await call(NativeLivePhoto.generate({ ...options, requestId }));
  } finally {
    subscription?.remove();
    signal?.removeEventListener('abort', abort);
  }
}

const cancelled = () =>
  new LivePhotoError('E_CANCELLED', 'The operation was cancelled');

let lastRequestId = 0;

/**
 * Saves a Live Photo pair to the user's photo library as a single asset. Requests add-only
 * access if needed.
 */
export async function saveLivePhotoToLibrary(
  files: LivePhotoFiles
): Promise<SavedLivePhoto> {
  const assetId = await call(
    NativeLivePhoto.saveToLibrary(files.photoUri, files.videoUri)
  );
  return { assetId };
}

export function requestPhotoLibraryPermission(
  accessLevel: PhotoLibraryAccessLevel = 'addOnly'
): Promise<PhotoLibraryPermissionStatus> {
  return call(
    NativeLivePhoto.requestPermission(
      accessLevel
    ) as Promise<PhotoLibraryPermissionStatus>
  );
}

/**
 * Lets the user pick a Live Photo with the system photo picker and copies its photo and
 * video into the cache. Resolves with `null` if the user cancels. Needs no photo library
 * permission.
 */
export function pickLivePhoto(): Promise<PickedLivePhoto | null> {
  return call(NativeLivePhoto.pick());
}

/**
 * Deletes all files generated or downloaded by this library. Files returned by
 * `generateLivePhoto` stop existing, so save or copy them first if you need them.
 */
export function clearLivePhotoCache(): Promise<void> {
  return call(NativeLivePhoto.clearCache());
}
