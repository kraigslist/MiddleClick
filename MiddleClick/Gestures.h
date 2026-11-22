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

bool TapFrameCompletesTap(TapState* tap, const GestureSettings* settings, const Finger* fingers, int nFingers, double timestamp);

typedef struct {
  bool fingersDown;
  bool middleIsDown;
} ClickState;

bool ClickBecomesMiddle(ClickState* click, bool isButtonDown);

#endif
