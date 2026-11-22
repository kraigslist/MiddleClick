#include "Gestures.h"
#include <math.h>

bool TapFrame(TapState* tap, const GestureSettings* settings, const Finger* fingers, int nFingers, double timestamp)
{
  bool isTap = false;

  if (nFingers == 0) {
    double elapsedTime = tap->isTouching ? timestamp - tap->touchStartTime : 0;
    tap->isTouching = false;
    if (tap->startX + tap->startY != 0 && elapsedTime <= settings->maxTimeDelta) {
      float delta = fabsf(tap->startX - tap->endX) + fabsf(tap->startY - tap->endY);
      isTap = delta < settings->maxDistanceDelta;
    }
  } else if (!tap->isTouching) {
    tap->isTouching = true;
    tap->touchStartTime = timestamp;
    tap->maybeMiddleClick = true;
    tap->startX = 0;
    tap->startY = 0;
  } else if (tap->maybeMiddleClick && timestamp - tap->touchStartTime > settings->maxTimeDelta) {
    tap->maybeMiddleClick = false;
  }

  if (nFingers > settings->fingers) {
    tap->maybeMiddleClick = false;
    tap->startX = 0;
    tap->startY = 0;
  }

  if (nFingers == settings->fingers) {
    float x = 0, y = 0;
    for (int i = 0; i < nFingers; i++) {
      x += fingers[i].normalized.pos.x;
      y += fingers[i].normalized.pos.y;
    }
    if (tap->maybeMiddleClick) {
      tap->startX = x;
      tap->startY = y;
      tap->maybeMiddleClick = false;
    }
    tap->endX = x;
    tap->endY = y;
  }

  return isTap;
}

bool ClickRemap(ClickState* click, bool isButtonDown)
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
