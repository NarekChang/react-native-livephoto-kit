// Imports the Swift-generated header. Its module imports are skipped in Objective-C++
// without -fcxx-modules, so the frameworks it references are imported explicitly first.
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

#if __has_include(<RNLivePhoto/RNLivePhoto-Swift.h>)
#import <RNLivePhoto/RNLivePhoto-Swift.h>
#else
#import "RNLivePhoto-Swift.h"
#endif
