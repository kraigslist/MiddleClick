#include "WindowFrame.h"
#include <stdio.h>

static int failures;

static void expect(bool ok, const char* name)
{
  printf("%s  %s\n", ok ? "ok  " : "FAIL", name);
  failures += !ok;
}

static bool sameRect(WindowRect a, WindowRect b)
{
  return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;
}

static const WindowRect usable = {0, 25, 1512, 900};

static void filled(void)
{
  expect(WindowFrameIsFilled(usable, usable, 24), "a window matching the usable area is filled");

  expect(WindowFrameIsFilled((WindowRect){0, 25, 1505, 890}, usable, 24),
         "a window a few points short, like Terminal snapping to rows, is filled");

  expect(!WindowFrameIsFilled((WindowRect){0, 25, 1000, 900}, usable, 24),
         "a full-height window that isn't full width isn't filled");

  expect(!WindowFrameIsFilled((WindowRect){200, 125, 800, 600}, usable, 24),
         "an ordinary window isn't filled");
}

static void shrink(void)
{
  WindowRect shrunk = WindowFrameCenteredShrink(usable, 2.0 / 3);
  expect(sameRect(shrunk, (WindowRect){252, 175, 1008, 600}),
         "the shrunk window is two-thirds the size, centered in the usable area");

  expect(!WindowFrameIsFilled(shrunk, usable, 24), "the shrunk window no longer counts as filled");
}

static void screens(void)
{
  WindowRect displays[] = {{0, 0, 1512, 982}, {1512, 0, 2560, 1440}};

  expect(WindowFrameScreenIndex((WindowRect){100, 100, 800, 600}, displays, 2) == 0,
         "a window on the built-in display picks it");

  expect(WindowFrameScreenIndex((WindowRect){1400, 100, 800, 600}, displays, 2) == 1,
         "a window straddling two displays picks the one it's mostly on");

  expect(WindowFrameScreenIndex((WindowRect){-5000, -5000, 100, 100}, displays, 2) == 0,
         "a window off every display falls back to the first");

  expect(WindowFrameScreenIndex(usable, displays, 0) == -1, "no displays gives no index");
}

static void flipped(void)
{
  expect(sameRect(WindowFrameFlipped((WindowRect){0, 57, 1512, 900}, 982), (WindowRect){0, 25, 1512, 900}),
         "a Cocoa frame flips to top-left coordinates");

  expect(sameRect(WindowFrameFlipped((WindowRect){1512, -458, 2560, 1440}, 982), (WindowRect){1512, 0, 2560, 1440}),
         "a taller display beside the primary one flips by the primary's height");
}

int main(void)
{
  filled();
  shrink();
  screens();
  flipped();
  return failures != 0;
}
