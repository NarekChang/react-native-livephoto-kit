import { describe, expect, it } from '@jest/globals';

const withLivePhoto = require('../../app.plugin') as <
  T extends { ios?: { infoPlist?: Record<string, unknown> } },
>(
  config: T,
  props?: { savePhotosPermission?: string | false; photosPermission?: string }
) => T;

type ExpoConfig = {
  name: string;
  slug: string;
  ios?: { bundleIdentifier?: string; infoPlist?: Record<string, unknown> };
};

const base: ExpoConfig = { name: 'App', slug: 'app' };

describe('Expo config plugin', () => {
  it('adds the save permission by default and nothing else', () => {
    const config = withLivePhoto(base);
    expect(config.ios?.infoPlist).toEqual({
      NSPhotoLibraryAddUsageDescription:
        'Allow $(PRODUCT_NAME) to save Live Photos to your photo library.',
    });
    expect(config).toMatchObject(base);
  });

  it('uses custom descriptions and adds read access only when asked', () => {
    const config = withLivePhoto(base, {
      savePhotosPermission: 'Save it',
      photosPermission: 'Show them',
    });
    expect(config.ios?.infoPlist).toEqual({
      NSPhotoLibraryAddUsageDescription: 'Save it',
      NSPhotoLibraryUsageDescription: 'Show them',
    });
  });

  it('keeps existing Info.plist entries and descriptions from app.json', () => {
    const config = withLivePhoto({
      ...base,
      ios: {
        bundleIdentifier: 'com.example',
        infoPlist: {
          NSPhotoLibraryAddUsageDescription: 'From app.json',
          UIBackgroundModes: ['audio'],
        },
      },
    });
    expect(config.ios).toEqual({
      bundleIdentifier: 'com.example',
      infoPlist: {
        NSPhotoLibraryAddUsageDescription: 'From app.json',
        UIBackgroundModes: ['audio'],
      },
    });
  });

  it('leaves the save permission out with false', () => {
    const config = withLivePhoto(base, { savePhotosPermission: false });
    expect(config.ios?.infoPlist).toEqual({});
  });

  it('does not mutate the input config', () => {
    const input = { ...base, ios: { infoPlist: {} } };
    withLivePhoto(input);
    expect(input.ios.infoPlist).toEqual({});
  });
});
