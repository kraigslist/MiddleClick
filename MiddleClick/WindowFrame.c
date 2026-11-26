#include "WindowFrame.h"
#include <math.h>

WindowRect WindowFrameFlipped(WindowRect frame, double primaryScreenHeight)
{
  frame.y = primaryScreenHeight - frame.y - frame.height;
  return frame;
}

bool WindowFrameIsFilled(WindowRect window, WindowRect usable, double tolerance)
{
  return fabs(window.x - usable.x) <= tolerance &&
         fabs(window.y - usable.y) <= tolerance &&
         fabs(window.x + window.width - (usable.x + usable.width)) <= tolerance &&
         fabs(window.y + window.height - (usable.y + usable.height)) <= tolerance;
}

WindowRect WindowFrameCenteredShrink(WindowRect usable, double scale)
{
  double width = round(usable.width * scale);
  double height = round(usable.height * scale);
  return (WindowRect){
    .x = usable.x + round((usable.width - width) / 2),
    .y = usable.y + round((usable.height - height) / 2),
    .width = width,
    .height = height,
  };
}

static double OverlapArea(WindowRect a, WindowRect b)
{
  double width = fmin(a.x + a.width, b.x + b.width) - fmax(a.x, b.x);
  double height = fmin(a.y + a.height, b.y + b.height) - fmax(a.y, b.y);
  return width > 0 && height > 0 ? width * height : 0;
}

int WindowFrameScreenIndex(WindowRect window, const WindowRect* screens, int count)
{
  int best = count > 0 ? 0 : -1;
  double bestArea = 0;
  for (int i = 0; i < count; i++) {
    double area = OverlapArea(window, screens[i]);
    if (area > bestArea) {
      best = i;
      bestArea = area;
    }
  }
  return best;
}
