---------------------------- MODULE ListenerLifecycle ----------------------------
(* How Controller.m and TrayMenu.m install and remove MiddleClick's listeners.
   Every handler runs on the main run loop, so each action is one callout that
   finishes before the next starts. Bug selects a replay of a past bug, or "none"
   for the current code. *)
EXTENDS Naturals

CONSTANT Bug

Bugs == {"none", "RestartLeak", "NoSessionGate", "SharedDebounce",
         "NoRevokeHandling", "TapInTapMode"}
ASSUME Bug \in Bugs

VARIABLES
  onConsole,    \* this user's session is on the console
  session,      \* Controller._isUserSessionActive
  click,        \* needToClick
  permitted,    \* the Accessibility permission, as AXIsProcessTrusted() reports it
  believed,     \* Controller._isAccessibilityTrusted
  touch,        \* currentDeviceList != NULL: touch callbacks registered
  tap,          \* currentEventTap != NULL, with currentRunLoopSource
  leaked,       \* listener resources created and never released
  restartArmed, \* Controller._restartTimer is scheduled
  checkArmed,   \* TrayMenu has an AXIsProcessTrusted() check scheduled
  debounce      \* SharedDebounce only: a resign happened under 0.5 s ago

vars == <<onConsole, session, click, permitted, believed, touch, tap, leaked,
          restartArmed, checkArmed, debounce>>

(* updateListeners, given the state it reads. An event tap is created only when
   the permission is really there; CGEventTapCreate returns NULL otherwise. *)
WantsTap(s, c, b) == s /\ (c \/ Bug = "TapInTapMode") /\ b

Update(s, c, b) ==
  /\ touch' = s
  /\ tap' = IF WantsTap(s, c, b) THEN tap \/ permitted ELSE FALSE

Init ==
  /\ onConsole = TRUE
  /\ session = TRUE
  /\ click \in BOOLEAN
  /\ permitted \in BOOLEAN
  /\ believed = permitted
  /\ touch = TRUE
  /\ tap = (WantsTap(TRUE, click, permitted) /\ permitted)
  /\ leaked = 0
  /\ restartArmed = FALSE
  /\ checkArmed = ~permitted       \* initAccessibilityPermissionStatus polls while untrusted
  /\ debounce = FALSE

(* receiveWakeNote, multitouchDeviceAddedCallback, displayReconfigurationCallBack *)
ScheduleRestart ==
  /\ restartArmed' = TRUE
  /\ UNCHANGED <<onConsole, session, click, permitted, believed, touch, tap,
                 leaked, checkArmed, debounce>>

(* restartListeners: unregister both listeners, then updateListeners *)
RestartFires ==
  /\ restartArmed
  /\ restartArmed' = FALSE
  /\ touch' = session
  /\ tap' = (WantsTap(session, click, believed) /\ permitted)
  /\ leaked' = IF Bug = "RestartLeak"
                 THEN leaked + (IF touch THEN 1 ELSE 0) + (IF tap THEN 1 ELSE 0)
                 ELSE leaked
  /\ UNCHANGED <<onConsole, session, click, permitted, believed, checkArmed, debounce>>

(* receiveSessionResignActiveNote *)
ResignActive ==
  /\ onConsole
  /\ onConsole' = FALSE
  /\ IF Bug = "NoSessionGate"
       THEN UNCHANGED <<session, touch, tap>>
       ELSE session' = FALSE /\ Update(FALSE, click, believed)
  /\ debounce' = (Bug = "SharedDebounce")
  /\ UNCHANGED <<click, permitted, believed, leaked, restartArmed, checkArmed>>

(* receiveSessionBecomeActiveNote *)
BecomeActive ==
  /\ ~onConsole
  /\ onConsole' = TRUE
  /\ IF Bug = "NoSessionGate" \/ (Bug = "SharedDebounce" /\ debounce)
       THEN UNCHANGED <<session, touch, tap>>
       ELSE session' = TRUE /\ Update(TRUE, click, believed)
  /\ UNCHANGED <<click, permitted, believed, leaked, restartArmed, checkArmed, debounce>>

DebounceEnds ==
  /\ debounce
  /\ debounce' = FALSE
  /\ UNCHANGED <<onConsole, session, click, permitted, believed, touch, tap,
                 leaked, restartArmed, checkArmed>>

(* setMode: and resetClickMode from the menu *)
SetMode ==
  /\ click' \in BOOLEAN
  /\ Update(session, click', believed)
  /\ UNCHANGED <<onConsole, session, permitted, believed, leaked, restartArmed,
                 checkArmed, debounce>>

(* The user changes the permission in System Settings. macOS posts
   com.apple.accessibility.api and receiveAccessibilityNote schedules a check. *)
Revoke ==
  /\ permitted
  /\ permitted' = FALSE
  /\ checkArmed' = IF Bug = "NoRevokeHandling" THEN checkArmed ELSE TRUE
  /\ UNCHANGED <<onConsole, session, click, believed, touch, tap, leaked,
                 restartArmed, debounce>>

Grant ==
  /\ ~permitted
  /\ permitted' = TRUE
  /\ checkArmed' = TRUE
  /\ UNCHANGED <<onConsole, session, click, believed, touch, tap, leaked,
                 restartArmed, debounce>>

(* initAccessibilityPermissionStatus: tell the controller, and poll again while untrusted *)
CheckFires ==
  /\ checkArmed
  /\ believed' = permitted
  /\ checkArmed' = ~permitted
  /\ Update(session, click, permitted)
  /\ UNCHANGED <<onConsole, session, click, permitted, leaked, restartArmed, debounce>>

Next ==
  \/ ScheduleRestart \/ RestartFires
  \/ ResignActive \/ BecomeActive \/ DebounceEnds
  \/ SetMode
  \/ Revoke \/ Grant \/ CheckFires

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* No pending timer of either kind and no debounce. *)
AtRest == ~restartArmed /\ ~checkArmed /\ ~debounce

(* Releasing listeners on every path leaves nothing behind (7249613). *)
NoLeaks == leaked = 0

(* A second logged-in session holding the devices stops frame delivery (864fc4f, #172). *)
NothingOffConsole == ~onConsole => ~touch /\ ~tap

(* Once the controller knows the permission is gone, the tap is gone,
   because a default tap without permission can block all mouse input (08b1415, #63). *)
NoTapOnceRevokeKnown == ~believed => ~tap

(* While the permission is missing, a check is on its way to notice it. *)
MissingPermissionIsChecked == ~permitted => checkArmed

(* With nothing pending, exactly the listeners the state calls for are installed (dd4aa91, #172). *)
Converged == AtRest => /\ touch = onConsole
                       /\ tap = (onConsole /\ click /\ permitted)

Bounded == leaked <= 2
=============================================================================
