//
//  SMCBridge.h
//  MacUnifiedUtility
//
//  Objective-C declarations for Apple Silicon HID sensor reading (via the
//  private IOHIDEventSystem API) and IOReport power sampling.
//
//  Function signatures follow exelban/stats bridge.h and the macOS IOKit
//  private framework. All APIs degrade gracefully on Intel or in a VM.
//

#pragma once
#include <CoreFoundation/CoreFoundation.h>

// MARK: - IOHIDEvent opaque types

typedef struct __IOHIDEvent          *IOHIDEventRef;
typedef struct __IOHIDServiceClient  *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float  IOHIDFloat;
#endif

#define IOHIDEventFieldBase(type) ((type) << 16)
#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventTypePower       25

// MARK: - IOHIDEventSystem private API

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int  IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                       CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                          int64_t  type,
                                          int32_t  options,
                                          int64_t  timeout);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service,
                                         CFStringRef property);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// MARK: - IOReport private API

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef a, CFStringRef b,
                                            uint64_t c, uint64_t d, uint64_t e);
void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef null);
IOReportSubscriptionRef IOReportCreateSubscription(void            *a,
                                                   CFMutableDictionaryRef  b,
                                                   CFMutableDictionaryRef *c,
                                                   uint64_t         d,
                                                   CFTypeRef        e);
CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef a,
                                      CFMutableDictionaryRef b,
                                      CFTypeRef c);
CFStringRef IOReportChannelGetGroup(CFDictionaryRef a);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef a);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef a);
int64_t     IOReportSimpleGetIntegerValue(CFDictionaryRef a, int32_t b);

// MARK: - Apple Silicon HID wrapper

/// Returns a dictionary mapping sensor product names (NSString) to their
/// current float readings (NSNumber). Returns nil if the system service is
/// unavailable (Intel, VM, or entitlement mismatch).
NSDictionary *AppleSiliconSensors(int32_t page, int32_t usage, int32_t type);
