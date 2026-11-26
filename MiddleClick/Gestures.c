#include "Gestures.h"
#include <math.h>

static bool IsTapFingerCount(const GestureSettings* settings, int nFingers)
{
  return nFingers == settings->fingers || (settings->fullscreenFingers > 0 && nFingers == settings->fullscreenFingers);
}

int TapFrameCompletesTapWithFingers(TapState* tap, const GestureSettings* settings, const Finger* fingers, int nFingers, double timestamp)
{
  int tapFingers = 0;

  if (nFingers == 0) {
    double elapsedTime = tap->isTouching ? timestamp - tap->touchStartTime : 0;
    tap->isTouching = false;
    if (tap->fingers > 0 && elapsedTime <= settings->maxTimeDelta) {
      float delta = fabsf(tap->startX - tap->endX) + fabsf(tap->startY - tap->endY);
      if (delta < settings->maxDistanceDelta) {
        tapFingers = tap->fingers;
      }
    }
    tap->fingers = 0;
  } else if (!tap->isTouching) {
    tap->isTouching = true;
    tap->touchStartTime = timestamp;
    tap->mayStart = true;
    tap->fingers = 0;
  } else if (tap->mayStart && timestamp - tap->touchStartTime > settings->maxTimeDelta) {
    tap->mayStart = false;
  }

  int maxTapFingers = settings->fullscreenFingers > settings->fingers ? settings->fullscreenFingers : settings->fingers;
  if (nFingers > maxTapFingers) {
    tap->mayStart = false;
    tap->fingers = 0;
  }

  if (IsTapFingerCount(settings, nFingers)) {
    float x = 0, y = 0;
    for (int i = 0; i < nFingers; i++) {
      x += fingers[i].normalized.pos.x;
      y += fingers[i].normalized.pos.y;
    }
    if (tap->mayStart && nFingers > tap->fingers) {
      tap->fingers = nFingers;
      tap->startX = x;
      tap->startY = y;
    }
    if (nFingers == tap->fingers) {
      tap->endX = x;
      tap->endY = y;
    }
  }

  return tapFingers;
}

bool ClickBecomesMiddle(ClickState* click, bool isButtonDown)
{
  if (isButtonDown && click->fingersDown) {
    click->fingersDown = false;
    click->middleIsDown = true;
    return true;
  }
  if (!isButtonDown && click->middleIsDown) {
    click->middleIsDown = false;
    return true;
  }
  return false;
}
