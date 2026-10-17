import type { LivePhotoErrorCode } from './types';

const codes: ReadonlySet<string> = new Set<LivePhotoErrorCode>([
  'E_INVALID_URI',
  'E_INVALID_INPUT',
  'E_DOWNLOAD',
  'E_WRITE',
  'E_PERMISSION',
  'E_ASSET_NOT_FOUND',
  'E_LOAD',
  'E_UNSUPPORTED',
  'E_CANCELLED',
  'E_UNKNOWN',
]);

/** Every promise of this library rejects with it, and `onError` receives it. */
export class LivePhotoError extends Error {
  readonly code: LivePhotoErrorCode;

  constructor(code: LivePhotoErrorCode, message: string) {
    super(message);
    // Keeps `instanceof` working when classes extending Error are transpiled.
    Object.setPrototypeOf(this, LivePhotoError.prototype);
    this.name = 'LivePhotoError';
    this.code = code;
  }
}

/** Converts a native promise rejection or error event payload into a `LivePhotoError`. */
export function toLivePhotoError(error: unknown): LivePhotoError {
  if (error instanceof LivePhotoError) {
    return error;
  }
  const { code, message } = (error ?? {}) as {
    code?: unknown;
    message?: unknown;
  };
  return new LivePhotoError(
    typeof code === 'string' && codes.has(code)
      ? (code as LivePhotoErrorCode)
      : 'E_UNKNOWN',
    typeof message === 'string' ? message : String(error)
  );
}
