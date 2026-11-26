#ifndef Gestures_h
#define Gestures_h

#include <stdbool.h>
#include "MultitouchSupport.h"

typedef struct {
  int fingers;
  int fullscreenFingers;
  float maxDistanceDelta;
  double maxTimeDelta;
} GestureSettings;

typedef struct {
  bool isTouching;
  double touchStartTime;
  bool mayStart;
  int fingers;
  float startX, startY;
  float endX, endY;
} TapState;

int TapFrameCompletesTapWithFingers(TapState* tap, const GestureSettings* settings, const Finger* fingers, int nFingers, double timestamp);

typedef struct {
  bool fingersDown;
  bool middleIsDown;
} ClickState;

bool ClickBecomesMiddle(ClickState* click, bool isButtonDown);

#endif
