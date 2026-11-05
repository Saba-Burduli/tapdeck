#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// Reverse-engineered layout of MultitouchSupport.framework (private API).
// Same layout used by MiddleClick / OpenMultitouchSupport. 96 bytes per touch.

#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
    int frame;
    double timestamp;
    int pathIndex;      // stable id for a finger while it stays on the pad
    int state;          // see MTTouchState in Swift
    int fingerID;
    int handID;
    MTVector normalized; // position 0..1, origin bottom-left
    float zTotal;        // contact size / pressure proxy
    int field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;   // millimetres
    int field14;
    int field15;
    float zDensity;
} MTTouch;

typedef void *MTDeviceRef;

typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

typedef CFMutableArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef, MTContactCallbackFunction);
typedef void (*MTDeviceStartFn)(MTDeviceRef, int);
typedef void (*MTDeviceStopFn)(MTDeviceRef);

#endif
