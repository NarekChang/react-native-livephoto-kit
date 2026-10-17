import {
  TurboModuleRegistry,
  type CodegenTypes,
  type TurboModule,
} from 'react-native';

export type GenerateOptions = Readonly<{
  videoUri: string;
  photoUri?: string;
  keyPhotoTime?: number;
  maxDuration?: number;
  // Set when the caller listens to progress or may cancel: echoed back in progress events
  // and accepted by cancelGenerate.
  requestId?: string;
}>;

export type LivePhotoFiles = Readonly<{
  photoUri: string;
  videoUri: string;
}>;

export type PickedLivePhoto = Readonly<{
  photoUri: string;
  videoUri: string;
  assetId?: string;
}>;

export type GenerateProgressEvent = Readonly<{
  requestId: string;
  progress: CodegenTypes.Double;
}>;

export interface Spec extends TurboModule {
  generate(options: GenerateOptions): Promise<LivePhotoFiles>;
  saveToLibrary(photoUri: string, videoUri: string): Promise<string>;
  requestPermission(accessLevel: string): Promise<string>;
  clearCache(): Promise<void>;
  cancelGenerate(requestId: string): void;
  pick(): Promise<PickedLivePhoto | null>;
  readonly onGenerateProgress: CodegenTypes.EventEmitter<GenerateProgressEvent>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('LivePhoto');
