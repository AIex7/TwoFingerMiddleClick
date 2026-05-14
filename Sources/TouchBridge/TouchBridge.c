#include "TouchBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef void *MTDeviceRef;
typedef struct MTFinger MTFinger;

typedef CFMutableArrayRef (*MTDeviceCreateListFunction)(void);
typedef void (*MTRegisterContactFrameCallbackFunction)(MTDeviceRef, int (*)(int, MTFinger *, int, double, int));
typedef void (*MTDeviceStartFunction)(MTDeviceRef, int);
typedef void (*MTDeviceStopFunction)(MTDeviceRef);

static void *frameworkHandle = NULL;
static CFMutableArrayRef devices = NULL;
static TFMCContactCallback contactCallback = NULL;
static MTDeviceStopFunction MTDeviceStopSymbol = NULL;

static void writeError(char *buffer, size_t length, const char *message) {
    if (buffer == NULL || length == 0) {
        return;
    }

    snprintf(buffer, length, "%s", message);
}

static int handleContactFrame(int device, MTFinger *fingers, int fingerCount, double timestamp, int frame) {
    (void)device;
    (void)frame;

    (void)fingers;

    if (contactCallback == NULL || fingerCount < 0) {
        return 0;
    }

    contactCallback(fingerCount, timestamp);
    return 0;
}

bool TFMCStartMultitouch(TFMCContactCallback callback, char *errorBuffer, size_t errorBufferLength) {
    contactCallback = callback;

    if (frameworkHandle == NULL) {
        frameworkHandle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY
        );
    }

    if (frameworkHandle == NULL) {
        writeError(errorBuffer, errorBufferLength, dlerror());
        return false;
    }

    MTDeviceCreateListFunction MTDeviceCreateListSymbol =
        (MTDeviceCreateListFunction)dlsym(frameworkHandle, "MTDeviceCreateList");
    MTRegisterContactFrameCallbackFunction MTRegisterContactFrameCallbackSymbol =
        (MTRegisterContactFrameCallbackFunction)dlsym(frameworkHandle, "MTRegisterContactFrameCallback");
    MTDeviceStartFunction MTDeviceStartSymbol =
        (MTDeviceStartFunction)dlsym(frameworkHandle, "MTDeviceStart");
    MTDeviceStopSymbol =
        (MTDeviceStopFunction)dlsym(frameworkHandle, "MTDeviceStop");

    if (MTDeviceCreateListSymbol == NULL ||
        MTRegisterContactFrameCallbackSymbol == NULL ||
        MTDeviceStartSymbol == NULL) {
        writeError(errorBuffer, errorBufferLength, "MultitouchSupport symbols were not available.");
        return false;
    }

    if (devices != NULL) {
        CFRelease(devices);
        devices = NULL;
    }

    devices = MTDeviceCreateListSymbol();
    if (devices == NULL || CFArrayGetCount(devices) == 0) {
        writeError(errorBuffer, errorBufferLength, "No multitouch devices were found.");
        return false;
    }

    CFIndex deviceCount = CFArrayGetCount(devices);
    for (CFIndex index = 0; index < deviceCount; index += 1) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, index);
        MTRegisterContactFrameCallbackSymbol(device, handleContactFrame);
        MTDeviceStartSymbol(device, 0);
    }

    writeError(errorBuffer, errorBufferLength, "");
    return true;
}

void TFMCStopMultitouch(void) {
    if (devices != NULL && MTDeviceStopSymbol != NULL) {
        CFIndex deviceCount = CFArrayGetCount(devices);
        for (CFIndex index = 0; index < deviceCount; index += 1) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, index);
            MTDeviceStopSymbol(device);
        }
    }

    if (devices != NULL) {
        CFRelease(devices);
        devices = NULL;
    }

    contactCallback = NULL;
}
