#include "Gestures.h"
#include "PreferenceKeys.h"
#include <stdio.h>

static int failures;

static void expect(bool ok, const char* name)
{
  printf("%s  %s\n", ok ? "ok  " : "FAIL", name);
  failures += !ok;
}

static const GestureSettings defaults = {
  kFingersNumDefault, kMaxDistanceDeltaDefault, kMaxTimeDeltaMsDefault / 1000.0,
};

typedef struct {
  int fingers;
  float slide;
  double time;
} Frame;

/// Slots past `fingers` hold values that change every frame, as the multitouch driver's buffer can.
static int countTaps(const GestureSettings* settings, const Frame* frames, int count)
{
  TapState tap = {0};
  int taps = 0;
  for (int f = 0; f < count; f++) {
    Finger buffer[8] = {0};
    for (int i = 0; i < 8; i++) {
      bool isTouching = i < frames[f].fingers;
      buffer[i].normalized.pos.x = isTouching ? 0.3f + 0.1f * i + frames[f].slide : 0.05f * f;
      buffer[i].normalized.pos.y = isTouching ? 0.5f : 0.07f * f;
    }
    taps += TapFrameCompletesTap(&tap, settings, buffer, frames[f].fingers, frames[f].time);
  }
  return taps;
}

#define TAPS(settings, ...) \
  countTaps(settings, (Frame[]){__VA_ARGS__}, sizeof((Frame[]){__VA_ARGS__}) / sizeof(Frame))

static void tapMode(void)
{
  expect(TAPS(&defaults, {3, 0, 0}, {3, 0, 0.05}, {0, 0, 0.1}) == 1,
         "a quick three-finger tap middle-clicks");

  expect(TAPS(&defaults, {1, 0, 0}, {2, 0, 0.02}, {3, 0, 0.04}, {0, 0, 0.1}) == 1,
         "fingers that land one after another still tap");

  expect(TAPS(&defaults, {3, 0, 0}, {0, 0, 0.1}, {3, 0, 0.5}, {0, 0, 0.6}) == 2,
         "each tap clicks once");

  GestureSettings twoFingers = defaults;
  twoFingers.fingers = 2;
  expect(TAPS(&twoFingers, {2, 0, 0}, {2, 0, 0.05}, {0, 0, 0.1}) == 1,
         "the configured finger count is used, not three (6da864a)");

  expect(TAPS(&defaults, {3, 0, 0}, {3, 0, 0.2}, {3, 0, 0.4}, {0, 0, 0.45}) == 0,
         "fingers resting past the time limit don't click (ec70590, #39)");

  expect(TAPS(&defaults, {3, 0, 0}, {3, 0.1f, 0.05}, {0, 0, 0.1}) == 0,
         "fingers that slide don't click (2d4cc54, #39)");

  expect(TAPS(&defaults, {3, 0, 0}, {4, 0, 0.03}, {3, 0, 0.06}, {0, 0, 0.1}) == 0,
         "an extra finger cancels the tap");
}

static void clickMode(void)
{
  ClickState click = {0};
  expect(!ClickBecomesMiddle(&click, true) && !ClickBecomesMiddle(&click, false),
         "a click without the fingers down stays a left click");

  click = (ClickState){.fingersDown = true};
  bool down = ClickBecomesMiddle(&click, true);
  bool up = ClickBecomesMiddle(&click, false);
  expect(down && up, "a click with the fingers down is a middle click, press and release");

  click = (ClickState){.fingersDown = true};
  ClickBecomesMiddle(&click, true);
  click.fingersDown = false;
  expect(ClickBecomesMiddle(&click, false), "the release stays middle when the fingers lift first");

  click = (ClickState){.fingersDown = true};
  ClickBecomesMiddle(&click, true);
  ClickBecomesMiddle(&click, false);
  expect(!ClickBecomesMiddle(&click, true), "the next click is a left click until the fingers are seen again (3f3aa45)");
}

int main(void)
{
  tapMode();
  clickMode();
  return failures != 0;
}
