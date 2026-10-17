import { useCallback, useEffect, useRef, useState } from 'react';
import { generateLivePhoto } from './api';
import { toLivePhotoError, type LivePhotoError } from './errors';
import type { GenerateLivePhotoOptions, LivePhotoFiles } from './types';

export type GenerateLivePhotoStatus =
  'idle' | 'generating' | 'success' | 'error';

export type GenerateLivePhotoState = {
  status: GenerateLivePhotoStatus;
  /** 0…1 while generating, 1 on success. */
  progress: number;
  result?: LivePhotoFiles;
  error?: LivePhotoError;
};

const idle: GenerateLivePhotoState = { status: 'idle', progress: 0 };

/**
 * `generateLivePhoto` with progress and status tracked in state. `generate` never throws:
 * it resolves with the files, or with `undefined` and sets `error`. Calling `generate`
 * again cancels the previous call, as does unmounting the component.
 */
export function useGenerateLivePhoto() {
  const [state, setState] = useState(idle);
  const latestCall = useRef(0);
  const controller = useRef<AbortController | null>(null);
  const mounted = useRef(true);

  // Invalidates the running call so it can't touch the state, and stops its native work.
  const abortCurrent = useCallback(() => {
    latestCall.current++;
    controller.current?.abort();
    controller.current = null;
  }, []);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      abortCurrent();
    };
  }, [abortCurrent]);

  const generate = useCallback(
    async (
      options: Omit<GenerateLivePhotoOptions, 'onProgress' | 'signal'>
    ): Promise<LivePhotoFiles | undefined> => {
      abortCurrent();
      const call = latestCall.current;
      const isCurrent = () => mounted.current && call === latestCall.current;
      const callController = new AbortController();
      controller.current = callController;

      setState({ status: 'generating', progress: 0 });
      try {
        const result = await generateLivePhoto({
          ...options,
          signal: callController.signal,
          onProgress: (progress) => {
            if (isCurrent()) {
              setState((current) => ({ ...current, progress }));
            }
          },
        });
        if (isCurrent()) {
          controller.current = null;
          setState({ status: 'success', progress: 1, result });
        }
        return result;
      } catch (error) {
        if (isCurrent()) {
          controller.current = null;
          setState({
            status: 'error',
            progress: 0,
            error: toLivePhotoError(error),
          });
        }
        return undefined;
      }
    },
    [abortCurrent]
  );

  /** Stops a running generation; the state goes back to `idle`. No-op otherwise. */
  const cancel = useCallback(() => {
    if (controller.current) {
      abortCurrent();
      setState(idle);
    }
  }, [abortCurrent]);

  /** Cancels a running generation and clears `result` and `error`. */
  const reset = useCallback(() => {
    abortCurrent();
    setState(idle);
  }, [abortCurrent]);

  return { ...state, generate, cancel, reset };
}
