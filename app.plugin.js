// Expo config plugin: `plugins: ["react-native-livephoto-kit"]` in app.json.
//
// It only sets `ios.infoPlist`, which Expo prebuild merges into Info.plist, so it needs no
// dependency on @expo/config-plugins.

const SAVE_PHOTOS_PERMISSION =
  'Allow $(PRODUCT_NAME) to save Live Photos to your photo library.';

/**
 * @typedef {object} LivePhotoPluginProps
 * @property {string | false} [savePhotosPermission] `NSPhotoLibraryAddUsageDescription`, needed
 *   by `saveLivePhotoToLibrary()`. Set by default; pass `false` to leave it out.
 * @property {string} [photosPermission] `NSPhotoLibraryUsageDescription`, needed only to show
 *   library assets with `source={{ assetId }}`. Not set unless given.
 */

/**
 * @template {{ ios?: { infoPlist?: Record<string, unknown> } }} Config
 * @param {Config} config
 * @param {LivePhotoPluginProps | void} props
 * @returns {Config}
 */
function withLivePhoto(config, props) {
  const { savePhotosPermission, photosPermission } = props || {};
  const infoPlist = { ...config.ios?.infoPlist };

  // Explicit plugin props win; otherwise a description already in app.json is kept.
  if (savePhotosPermission !== false) {
    infoPlist.NSPhotoLibraryAddUsageDescription =
      savePhotosPermission ||
      infoPlist.NSPhotoLibraryAddUsageDescription ||
      SAVE_PHOTOS_PERMISSION;
  }
  if (photosPermission) {
    infoPlist.NSPhotoLibraryUsageDescription = photosPermission;
  }

  return { ...config, ios: { ...config.ios, infoPlist } };
}

module.exports = withLivePhoto;
