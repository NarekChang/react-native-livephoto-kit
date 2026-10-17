import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { act, renderHook } from '@testing-library/react-native';
import { toNativeAutoplay } from '../autoplay';
import { LivePhotoError, toLivePhotoError } from '../errors';

type ProgressListener = (event: {
  requestId: string;
  progress: number;
}) => void;
const mockProgressListeners = new Set<ProgressListener>();
const emitProgress = (requestId: string, progress: number) =>
  mockProgressListeners.forEach((listener) =>
    listener({ requestId, progress })
  );

const mockNative = {
  generate: jest.fn(async (_options: unknown) => ({
    photoUri: 'file:///p.jpg',
    videoUri: 'file:///v.mov',
  })),
  saveToLibrary: jest.fn(
    async (_photoUri: string, _videoUri: string) => 'asset-id'
  ),
  requestPermission: jest.fn(async (_level: string) => 'authorized'),
  clearCache: jest.fn(async () => undefined),
  cancelGenerate: jest.fn((_requestId: string) => {}),
  pick: jest.fn(
    async (): Promise<{
      photoUri: string;
      videoUri: string;
      assetId?: string;
    } | null> => null
  ),
  onGenerateProgress: jest.fn((listener: ProgressListener) => {
    mockProgressListeners.add(listener);
    return { remove: () => mockProgressListeners.delete(listener) };
  }),
};

jest.mock('../NativeLivePhoto', () => ({
  __esModule: true,
  default: mockNative,
}));

const api = require('../api.ios') as typeof import('../api.ios');
const { useGenerateLivePhoto } =
  require('../useGenerateLivePhoto') as typeof import('../useGenerateLivePhoto');

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

const files = { photoUri: 'file:///p.jpg', videoUri: 'file:///v.mov' };

describe('iOS API', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('passes generate options through to the native module', async () => {
    const options = {
      videoUri: 'file:///in.mov',
      keyPhotoTime: 1.5,
      maxDuration: 3,
    };
    await expect(api.generateLivePhoto(options)).resolves.toEqual({
      photoUri: 'file:///p.jpg',
      videoUri: 'file:///v.mov',
    });
    expect(mockNative.generate).toHaveBeenCalledWith(options);
  });

  it('does not subscribe to progress without onProgress', async () => {
    await api.generateLivePhoto({ videoUri: 'file:///in.mov' });
    expect(mockNative.onGenerateProgress).not.toHaveBeenCalled();
    expect(mockNative.generate).toHaveBeenCalledWith({
      videoUri: 'file:///in.mov',
    });
  });

  it('reports progress of its own request only and unsubscribes', async () => {
    const pending = deferred<typeof files>();
    mockNative.generate.mockImplementationOnce(() => pending.promise);
    const onProgress = jest.fn();

    const result = api.generateLivePhoto({
      videoUri: 'file:///in.mov',
      onProgress,
    });
    const { requestId } = mockNative.generate.mock.calls[0]![0] as {
      requestId: string;
    };
    expect(requestId).toEqual(expect.any(String));

    emitProgress(requestId, 0.5);
    emitProgress('another-request', 0.9);
    pending.resolve(files);
    await result;

    expect(onProgress.mock.calls).toEqual([[0.5]]);
    expect(mockProgressListeners.size).toBe(0);
  });

  it('unsubscribes from progress when generation fails', async () => {
    mockNative.generate.mockRejectedValueOnce(
      Object.assign(new Error('nope'), { code: 'E_WRITE' })
    );
    await expect(
      api.generateLivePhoto({ videoUri: 'x', onProgress: () => {} })
    ).rejects.toMatchObject({ code: 'E_WRITE' });
    expect(mockProgressListeners.size).toBe(0);
  });

  it('cancels the native generation when the signal aborts', async () => {
    const pending = deferred<typeof files>();
    mockNative.generate.mockImplementationOnce(() => pending.promise);
    const controller = new AbortController();

    const result = api.generateLivePhoto({
      videoUri: 'x',
      signal: controller.signal,
    });
    const { requestId } = mockNative.generate.mock.calls[0]![0] as {
      requestId: string;
    };
    controller.abort();
    expect(mockNative.cancelGenerate).toHaveBeenCalledWith(requestId);

    pending.reject(
      Object.assign(new Error('cancelled'), { code: 'E_CANCELLED' })
    );
    await expect(result).rejects.toMatchObject({ code: 'E_CANCELLED' });
    expect(mockNative.onGenerateProgress).not.toHaveBeenCalled();
  });

  it('does not call native when the signal is already aborted', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(
      api.generateLivePhoto({ videoUri: 'x', signal: controller.signal })
    ).rejects.toMatchObject({ code: 'E_CANCELLED' });
    expect(mockNative.generate).not.toHaveBeenCalled();
  });

  it('stops listening to the signal once generation finishes', async () => {
    const controller = new AbortController();
    await api.generateLivePhoto({ videoUri: 'x', signal: controller.signal });
    controller.abort();
    expect(mockNative.cancelGenerate).not.toHaveBeenCalled();
  });

  it('resolves pickLivePhoto with the picked files or null', async () => {
    await expect(api.pickLivePhoto()).resolves.toBeNull();
    mockNative.pick.mockResolvedValueOnce({ ...files, assetId: 'id' });
    await expect(api.pickLivePhoto()).resolves.toEqual({
      ...files,
      assetId: 'id',
    });
  });

  it('saves the photo and video pair', async () => {
    await expect(
      api.saveLivePhotoToLibrary({
        photoUri: 'file:///p.jpg',
        videoUri: 'file:///v.mov',
      })
    ).resolves.toEqual({ assetId: 'asset-id' });
    expect(mockNative.saveToLibrary).toHaveBeenCalledWith(
      'file:///p.jpg',
      'file:///v.mov'
    );
  });

  it('requests add-only access by default', async () => {
    await api.requestPhotoLibraryPermission();
    expect(mockNative.requestPermission).toHaveBeenCalledWith('addOnly');
  });

  it('clears the cache', async () => {
    await api.clearLivePhotoCache();
    expect(mockNative.clearCache).toHaveBeenCalled();
  });

  it('rejects with LivePhotoError carrying the native code', async () => {
    mockNative.generate.mockRejectedValueOnce(
      Object.assign(new Error('Invalid URI: x'), { code: 'E_INVALID_URI' })
    );
    const error = await api
      .generateLivePhoto({ videoUri: 'x' })
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(LivePhotoError);
    expect(error).toMatchObject({
      code: 'E_INVALID_URI',
      message: 'Invalid URI: x',
    });
  });
});

describe('toLivePhotoError', () => {
  it('maps event payloads and unknown codes', () => {
    expect(
      toLivePhotoError({ code: 'E_LOAD', message: 'bad pair' })
    ).toMatchObject({
      code: 'E_LOAD',
      message: 'bad pair',
    });
    expect(
      toLivePhotoError({ code: 'EUNSPECIFIED', message: 'boom' }).code
    ).toBe('E_UNKNOWN');
    expect(toLivePhotoError('boom')).toMatchObject({
      code: 'E_UNKNOWN',
      message: 'boom',
    });
  });
});

describe('toNativeAutoplay', () => {
  it('maps the public prop to the native enum', () => {
    expect(toNativeAutoplay(undefined)).toBe('off');
    expect(toNativeAutoplay(false)).toBe('off');
    expect(toNativeAutoplay(true)).toBe('hint');
    expect(toNativeAutoplay('full')).toBe('full');
  });
});

describe('other platforms', () => {
  it('rejects every call with E_UNSUPPORTED', async () => {
    // Explicit extension: the default Jest platform is iOS and would resolve api.ios.ts.
    const fallback = require('../api.ts') as typeof import('../api');
    for (const call of [
      () => fallback.generateLivePhoto({ videoUri: 'x' }),
      () => fallback.requestPhotoLibraryPermission(),
      () => fallback.clearLivePhotoCache(),
      () => fallback.pickLivePhoto(),
    ]) {
      await expect(call()).rejects.toMatchObject({ code: 'E_UNSUPPORTED' });
    }
  });
});

describe('useGenerateLivePhoto', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('tracks progress and the result', async () => {
    const pending = deferred<typeof files>();
    mockNative.generate.mockImplementationOnce(() => pending.promise);
    const { result } = await renderHook(() => useGenerateLivePhoto());
    expect(result.current.status).toBe('idle');

    let generated: Promise<unknown> | undefined;
    await act(async () => {
      generated = result.current.generate({ videoUri: 'file:///in.mov' });
    });
    expect(result.current).toMatchObject({ status: 'generating', progress: 0 });

    const { requestId } = mockNative.generate.mock.calls[0]![0] as {
      requestId: string;
    };
    await act(async () => emitProgress(requestId, 0.4));
    expect(result.current.progress).toBe(0.4);

    await act(async () => {
      pending.resolve(files);
      await generated;
    });
    expect(result.current).toMatchObject({
      status: 'success',
      progress: 1,
      result: files,
    });
  });

  it('stores the error instead of throwing', async () => {
    mockNative.generate.mockRejectedValueOnce(
      Object.assign(new Error('bad uri'), { code: 'E_INVALID_URI' })
    );
    const { result } = await renderHook(() => useGenerateLivePhoto());

    let returned: unknown = 'not called';
    await act(async () => {
      returned = await result.current.generate({ videoUri: 'x' });
    });
    expect(returned).toBeUndefined();
    expect(result.current.status).toBe('error');
    expect(result.current.error).toMatchObject({
      code: 'E_INVALID_URI',
      message: 'bad uri',
    });
  });

  it('ignores a call superseded by a newer one, and reset', async () => {
    const first = deferred<typeof files>();
    const second = deferred<typeof files>();
    mockNative.generate
      .mockImplementationOnce(() => first.promise)
      .mockImplementationOnce(() => second.promise);
    const { result } = await renderHook(() => useGenerateLivePhoto());

    await act(async () => {
      result.current.generate({ videoUri: 'first' });
      result.current.generate({ videoUri: 'second' });
    });
    const newer = { photoUri: 'file:///2.jpg', videoUri: 'file:///2.mov' };
    await act(async () => {
      second.resolve(newer);
      first.resolve(files);
    });
    expect(result.current.result).toEqual(newer);

    await act(async () => result.current.reset());
    expect(result.current).toMatchObject({ status: 'idle', progress: 0 });
    expect(result.current.result).toBeUndefined();
  });

  it('cancel() stops the running generation and returns to idle', async () => {
    const pending = deferred<typeof files>();
    mockNative.generate.mockImplementationOnce(() => pending.promise);
    const { result } = await renderHook(() => useGenerateLivePhoto());

    await act(async () => {
      result.current.generate({ videoUri: 'x' });
    });
    const { requestId } = mockNative.generate.mock.calls[0]![0] as {
      requestId: string;
    };
    await act(async () => result.current.cancel());
    expect(mockNative.cancelGenerate).toHaveBeenCalledWith(requestId);
    expect(result.current.status).toBe('idle');

    await act(async () => {
      pending.reject(
        Object.assign(new Error('cancelled'), { code: 'E_CANCELLED' })
      );
    });
    expect(result.current.status).toBe('idle');
    expect(result.current.error).toBeUndefined();
  });

  it('cancels the previous call when generate is called again, and on unmount', async () => {
    mockNative.generate.mockImplementation(() => new Promise(() => {}));
    const { result, unmount } = await renderHook(() => useGenerateLivePhoto());

    await act(async () => {
      result.current.generate({ videoUri: 'first' });
    });
    const firstId = (
      mockNative.generate.mock.calls[0]![0] as { requestId: string }
    ).requestId;
    await act(async () => {
      result.current.generate({ videoUri: 'second' });
    });
    expect(mockNative.cancelGenerate).toHaveBeenCalledWith(firstId);

    const secondId = (
      mockNative.generate.mock.calls[1]![0] as { requestId: string }
    ).requestId;
    await unmount();
    expect(mockNative.cancelGenerate).toHaveBeenCalledWith(secondId);
    mockNative.generate.mockReset();
  });
});
