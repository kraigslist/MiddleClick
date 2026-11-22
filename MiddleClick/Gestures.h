#ifndef Gestures_h
#define Gestures_h

#include <stdbool.h>
#include "MultitouchSupport.h"

typedef struct {
  int fingers;
  float maxDistanceDelta;
  double maxTimeDelta;
} GestureSettings;

typedef struct {
  bool isTouching;
  double touchStartTime;
  bool maybeMiddleClick;
  float startX, startY;
  float endX, endY;
} TapState;

/// Feeds one multitouch frame to the tap detector. Returns true when the frame completes a tap.
bool TapFrame(TapState* tap, const GestureSettings* settings, const Finger* fingers, int nFingers, double timestamp);

typedef struct {
  bool fingersDown;
  bool middleIsDown;
} ClickState;

/// Returns true when this left button event should become a middle button event.
bool ClickRemap(ClickState* click, bool isButtonDown);

#endif
