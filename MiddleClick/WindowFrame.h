#ifndef WindowFrame_h
#define WindowFrame_h

#include <stdbool.h>

typedef struct {
  double x, y;
  double width, height;
} WindowRect;

WindowRect WindowFrameFlipped(WindowRect frame, double primaryScreenHeight);

bool WindowFrameIsFilled(WindowRect window, WindowRect usable, double tolerance);

WindowRect WindowFrameCenteredShrink(WindowRect usable, double scale);

int WindowFrameScreenIndex(WindowRect window, const WindowRect* screens, int count);

#endif
