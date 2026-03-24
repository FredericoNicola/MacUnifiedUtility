//
//  SMCBridge.m
//  MacUnifiedUtility
//
//  Objective-C wrapper that reads Apple Silicon HID temperature / voltage
//  sensors via the private IOHIDEventSystem API. Based on the implementation
//  in exelban/stats Modules/Sensors/reader.m and MenuMeters.
//
//  Returns nil when the service is unavailable (Intel Mac, VM, etc.).
//

#import <Foundation/Foundation.h>
#import "SMCBridge.h"

NSDictionary *AppleSiliconSensors(int32_t page, int32_t usage, int32_t type) {
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage":     @(usage)
    };

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!system) { return nil; }

    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (!services) {
        CFRelease(system);
        return nil;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    CFIndex count = CFArrayGetCount(services);

    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef svc =
            (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);

        NSString *name =
            CFBridgingRelease(IOHIDServiceClientCopyProperty(svc, CFSTR("Product")));

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(svc, type, 0, 0);
        if (!event) { continue; }

        if (name) {
            double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type));
            result[name] = @(value);
        }

        CFRelease(event);
    }

    CFRelease(services);
    CFRelease(system);

    return result;
}
