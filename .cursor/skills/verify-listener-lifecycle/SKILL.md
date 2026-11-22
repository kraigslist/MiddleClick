---
name: verify-listener-lifecycle
description: Model-check how MiddleClick installs and removes its touch callbacks and event tap across wake, device, display, session switch, mode and Accessibility changes. Use before changing updateListeners, restartListeners, scheduleRestart, the session or wake handlers, setMode, resetClickMode, setAccessibilityTrusted, register/unregister*Callback in Controller.m, or the permission checks in TrayMenu.m.
---

# Verify the listener lifecycle

## What it promises

`formal/ListenerLifecycle.tla` checks every order of these events: wake, device added, display change, the restart timer, session resign and become-active, a mode change, and Accessibility being granted or revoked. A wrong order has frozen the mouse, left middle click dead after a user switch, and slowed the trackpad over time. Five invariants hold:

- `NoLeaks`. Every restart releases what it replaces (fixed before in 7249613 and upstream #113 and #133).
- `NothingOffConsole`. While this user's session is switched out, no touch callback or tap is installed (864fc4f, upstream #172).
- `NoTapOnceRevokeKnown`. Once the controller has learned that permission is gone, the tap is gone, because a default tap without permission can block all mouse input (08b1415, upstream #63).
- `MissingPermissionIsChecked`. While permission is missing, a `TrayMenu` check is scheduled to notice it.
- `Converged`. With no timer pending, exactly the listeners the state calls for are installed (dd4aa91).

## Run it

```sh
scripts/model-check.sh          # current design plus every replay, about 5 s
scripts/model-check.sh none     # current design only
```

It needs Java 11 or later. The script downloads TLA+ tools 1.7.4 into `~/.cache/tla` and verifies its SHA-256. CI runs it in the `model` job.

Output is one line per run. `passes none` means the current design holds every invariant. Each other line must read `caught <Bug> breaks <invariant>`, which shows that the invariant still catches the bug it was written for. `FAILS` or `MISSED` prints TLC's full log, ending in a counterexample trace.

## Read a failure

Read every result with the `/statechart` skill. It tells a violation as its shortest path of steps and charts the states when the check passes. Then map each step back to the code using the table below.

A real bug is a trace in which every step is something the code can do. A modeling error is a trace that starts from a state the code never reaches, or uses a step the code can't take. In that case, fix the model, not the invariant. For example, a tap present when the permission is missing at launch is impossible, because `CGEventTapCreate` returns NULL without permission. Never weaken an invariant until a trace passes.

## What maps to what

| Model | Code |
|---|---|
| `onConsole` | Whether this user's session is on the console |
| `session` | `Controller._isUserSessionActive` |
| `click` | `needToClick` |
| `permitted` | `AXIsProcessTrusted()` |
| `believed` | `Controller._isAccessibilityTrusted` |
| `touch` | `currentDeviceList != NULL` |
| `tap` | `currentEventTap != NULL` (with `currentRunLoopSource`) |
| `restartArmed` | `Controller._restartTimer` scheduled |
| `checkArmed` | A `TrayMenu` timer that will call `initAccessibilityPermissionStatus:` |
| `WantsTap`, `Update` | `-[Controller updateListeners]` |
| `ScheduleRestart` | `receiveWakeNote:`, `multitouchDeviceAddedCallback`, `displayReconfigurationCallBack` |
| `RestartFires` | `-[Controller restartListeners]` |
| `ResignActive`, `BecomeActive` | `receiveSessionResignActiveNote:`, `receiveSessionBecomeActiveNote:` |
| `SetMode` | `setMode:`, `resetClickMode` |
| `Revoke`, `Grant` | The user changes the permission, and `-[TrayMenu receiveAccessibilityNote:]` schedules a check |
| `CheckFires` | `-[TrayMenu initAccessibilityPermissionStatus:]` calling `setAccessibilityTrusted:` |

Each action is one callout on the main run loop. Every handler above runs there, so none interleaves with another.

## Replays

`Bug` selects one past bug to put back. `none` is the current code.

| Bug | Past code | Breaks |
|---|---|---|
| `RestartLeak` | Before 7249613, a restart unregistered but never released the tap, its source and the device list | `NoLeaks` |
| `NoSessionGate` | Before 864fc4f, nothing observed session switches | `NothingOffConsole` |
| `SharedDebounce` | Upstream before #172, a become-active within 0.5 s of a resign was dropped | `Converged` |
| `NoRevokeHandling` | Before 08b1415, nothing watched for the permission being revoked | `MissingPermissionIsChecked` |
| `TapInTapMode` | Before dd4aa91, the tap was installed whatever the mode | `Converged` |

## Scope and assumptions

- Covered are the events in the table and every order of them. The state space is small, about 44 distinct states for `none`, so the check is exhaustive and has no depth bound. `leaked` is capped at 2 only to keep the replays finite.
- `AXIsProcessTrusted()` is assumed to report the new permission by the time `TrayMenu`'s check runs, 0.5 s after the notification. If it lags longer, a revoked tap survives until the next notification. The model doesn't cover that.
- Not covered are the gap between a session switch and its notification, the tap re-enable in `mouseCallback`, the multitouch frame thread (`touchCallback` runs off the main run loop), and anything inside `Gestures.c`. `scripts/test.sh` covers `Gestures.c`.

## When the code changes

1. If a change touches anything in the mapping table, change the model to match in the same commit, then run `scripts/model-check.sh`.
2. A new event becomes a new action, and a new listener becomes a new variable that `Update` sets.
3. When you fix a lifecycle bug, add it as a `Bug` value, with the invariant it must break, to both the model and `scripts/model-check.sh`.
4. After confirming that the model describes the code at a newer commit, move the sync commit below forward. Moving it without that check makes the record a lie.

Last synced with the code at commit `fbe1c46` (`Delete comments that restate code, and name what they explained`).
