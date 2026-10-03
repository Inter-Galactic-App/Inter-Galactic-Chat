#ifndef NotificationExtension_Bridging_Header_h
#define NotificationExtension_Bridging_Header_h

// vodozemac's C ABI for decrypting Matrix events inside a Notification Service
// Extension. The header ships with the flutter_vodozemac package; the symbols
// live in libvodozemac_bindings_dart.a, which the Runner pod build already
// produces. This target reaches both through search paths plus an explicit
// -force_load, rather than by depending on the flutter_vodozemac pod, because
// that podspec pulls Flutter.framework and an extension-API-only target must
// not link it.
#import "vodozemac_ios_ffi_bindings.h"

#endif /* NotificationExtension_Bridging_Header_h */
