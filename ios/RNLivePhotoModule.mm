#import "RNLivePhotoModule.h"
#import "RNLivePhotoSwift.h"

#import <React/RCTUtils.h>

static NSNumber *_Nullable RNNumberFromOptional(std::optional<double> value)
{
  return value.has_value() ? @(value.value()) : nil;
}

@implementation RNLivePhotoModule

+ (NSString *)moduleName
{
  return @"LivePhoto";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeLivePhotoSpecJSI>(params);
}

- (void)generate:(JS::NativeLivePhoto::GenerateOptions &)options
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject
{
  // JS passes a request id only when it listens to progress or may cancel. Progress events
  // carry it so JS can match them; sending events nobody listens to is harmless.
  NSString *requestId = options.requestId();
  __weak RNLivePhotoModule *weakSelf = self;
  void (^onProgress)(double) = requestId == nil ? nil : ^(double progress) {
    [weakSelf emitOnGenerateProgress:@{@"requestId" : requestId, @"progress" : @(progress)}];
  };

  [RNLivePhotoModuleImpl generateWithVideoUri:options.videoUri()
                                     photoUri:options.photoUri()
                                 keyPhotoTime:RNNumberFromOptional(options.keyPhotoTime())
                                  maxDuration:RNNumberFromOptional(options.maxDuration())
                                    requestId:requestId
                                   onProgress:onProgress
                                      resolve:resolve
                                       reject:^(NSString *code, NSString *message) {
                                         reject(code, message, nil);
                                       }];
}

- (void)saveToLibrary:(NSString *)photoUri
             videoUri:(NSString *)videoUri
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject
{
  [RNLivePhotoModuleImpl saveToLibraryWithPhotoUri:photoUri
                                          videoUri:videoUri
                                           resolve:resolve
                                            reject:^(NSString *code, NSString *message) {
                                              reject(code, message, nil);
                                            }];
}

- (void)requestPermission:(NSString *)accessLevel
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject
{
  [RNLivePhotoModuleImpl requestPermissionWithAccessLevel:accessLevel resolve:resolve];
}

- (void)cancelGenerate:(NSString *)requestId
{
  [RNLivePhotoModuleImpl cancelGenerateWithRequestId:requestId];
}

- (void)pick:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [RNLivePhotoModuleImpl pickFrom:RCTPresentedViewController()
                            resolve:resolve
                             reject:^(NSString *code, NSString *message) {
                               reject(code, message, nil);
                             }];
  });
}

- (void)clearCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [RNLivePhotoModuleImpl clearCacheWithResolve:resolve
                                        reject:^(NSString *code, NSString *message) {
                                          reject(code, message, nil);
                                        }];
}

@end
