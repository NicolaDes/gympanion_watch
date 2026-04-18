import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Timer;
import Toybox.Attention;

// DashboardDelegate: handles all button input on the main workout dashboard.
//
// Button semantics after the pause/resume-button-remap:
//   START          : PAUSED -> resume; WORK/REST -> pause;
//                    IDLE/BLOCK_COMPLETE -> startSet (begin workout/next block).
//   BACK short tap : WORK -> complete set + notify phone;
//                    sequential REST -> cut rest short and begin next set.
//   BACK held <500ms : treated as short tap (above).
//   BACK held 500–3000ms : cancelled hold — no action.
//   BACK held >=3000ms : haptic pulse + exit confirmation dialog.
//
// Long-press UP (onMenu) is intentionally removed — START is the single
// source of pause/resume.
//
// Long-press detection uses onKeyPressed(evt) + onKeyReleased(evt) on
// WatchUi.KEY_ESC because onBack() only fires on a complete press-release
// cycle and exposes no timing. Returning true from both methods on ESC
// events suppresses the synthesized onBack.
// Note: this codebase targets fr265 / ConnectIQ 5.2.0, which does not
// expose KeyEvent.getType() constants (no PRESS_TYPE_* or KEY_PRESSED/
// KEY_RELEASED symbols). Hence the two-method pattern.
class DashboardDelegate extends WatchUi.BehaviorDelegate {

    private var _engine      as WorkoutEngine;
    private var _commService as CompanionCommService;
    private var _finishTimer as Timer.Timer or Null;

    // Hold-to-exit state (BACK button).
    private var _backHoldTimer       as Timer.Timer or Null;
    private var _backHoldStartMs     as Number;
    private var _backHoldProgress    as Float;
    private var _backLongPressFired  as Boolean;

    function initialize(engine as WorkoutEngine, commService as CompanionCommService) {
        BehaviorDelegate.initialize();
        _engine      = engine;
        _commService = commService;
        _finishTimer = null;

        _backHoldTimer       = null;
        _backHoldStartMs     = 0;
        _backHoldProgress    = 0.0;
        _backLongPressFired  = false;

        _engine.setOnFinished(method(:_onWorkoutFinished));
    }

    // Read by DashboardView to render the hold-to-exit progress ring.
    // 0.0 = no hold in progress; 1.0 = threshold reached.
    function getBackHoldProgress() as Float {
        return _backHoldProgress;
    }

    // START/SELECT. Semantics:
    //   PAUSED                    -> resume
    //   WORK or REST              -> pause
    //   IDLE or BLOCK_COMPLETE    -> startSet (begin workout / next block)
    //   FINISHED or anything else -> no-op
    function onSelect() as Boolean {
        var state = _engine.getCurrentState();
        if (state == null) { return true; }
        var phase = state.phase;

        if (phase == PHASE_PAUSED) {
            _engine.resumeSession();
            return true;
        }

        if (phase == PHASE_WORK || phase == PHASE_REST) {
            _engine.pauseSession();
            return true;
        }

        if (phase == PHASE_IDLE || phase == PHASE_BLOCK_COMPLETE) {
            _engine.startSet();
            return true;
        }

        return true;
    }

    // Press-down on BACK starts the hold detector. Returning true suppresses
    // the BehaviorDelegate.onBack() synthesis that would otherwise fire on release.
    // Other keys fall through (return false) so onSelect() still fires for START.
    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ESC) { return false; }

        _backHoldStartMs = System.getTimer();
        _backLongPressFired = false;
        _backHoldProgress = 0.0;
        if (_backHoldTimer != null) {
            _backHoldTimer.stop();
        }
        _backHoldTimer = new Timer.Timer();
        _backHoldTimer.start(method(:_onBackHoldTick), 100, true);  // repeat every 100 ms
        WatchUi.requestUpdate();
        return true;
    }

    // Release on BACK stops the timer and decides what the press meant:
    //   <500 ms                    -> _handleBackShort() (phase-aware advance)
    //   500 ms <= held < 3000 ms   -> cancelled hold, no-op
    //   >=3000 ms                  -> long-press already fired the dialog; nothing to do
    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ESC) { return false; }

        if (_backHoldTimer != null) {
            _backHoldTimer.stop();
            _backHoldTimer = null;
        }
        var held = System.getTimer() - _backHoldStartMs;
        _backHoldProgress = 0.0;
        WatchUi.requestUpdate();

        if (_backLongPressFired) {
            return true;
        }
        if (held < 500) {
            _handleBackShort();
        }
        // 500 <= held < 3000 -> cancelled hold, no-op.
        return true;
    }

    // Consume the synthesized onBack so the dashboard never pops back to the
    // WorkoutSummary menu. Real BACK behaviour (short-press advance, cancelled
    // hold, 3 s exit dialog) is handled in onKeyPressed / onKeyReleased above.
    function onBack() as Boolean {
        return true;
    }

    // Phase-aware advance, invoked from a short press of BACK.
    // Reproduces the WORK and sequential-REST branches that used to live in onSelect().
    private function _handleBackShort() as Void {
        var state = _engine.getCurrentState();
        if (state == null) { return; }
        var phase = state.phase;

        // REST during sequential: cut rest short, start next set.
        if (phase == PHASE_REST) {
            var restBlock = _engine.getCurrentBlock();
            if (restBlock != null && restBlock.type == BLOCK_SEQUENTIAL) {
                _engine.startSet();
            }
            // EMOM REST: interval cannot be skipped — no-op.
            return;
        }

        // WORK: mark current exercise/set done and notify the phone.
        if (phase == PHASE_WORK) {
            var block = _engine.getCurrentBlock();
            if (block == null) { return; }

            var targetWeight = _engine.getCurrentTargetWeight();
            var targetReps   = _engine.getCurrentTargetReps();
            var exerciseName = _engine.getCurrentExerciseName();

            var payload = {
                "type"           => "set_complete",
                "exerciseName"   => exerciseName,
                "blockIndex"     => state.currentBlockIndex,
                "exerciseIndex"  => state.currentExerciseIndex,
                "setIndex"       => state.currentSetIndex,
                "durationMs"     => state.timerValueMs,
                "targetWeight"   => targetWeight,
                "targetReps"     => targetReps
            };

            if (block.type == BLOCK_EMOM) {
                payload.put("roundIndex", state.currentRoundIndex);
            } else if (block.type == BLOCK_AMRAP) {
                payload.put("amrapRound", state.amrapRoundsCompleted);
            }

            _commService.sendSetComplete(payload);
            _engine.completeSet(targetWeight, targetReps);
            return;
        }

        // All other phases (IDLE, BLOCK_COMPLETE, PAUSED, FINISHED): no-op.
    }

    // Fired every ~100 ms while BACK is held. Updates the progress ring;
    // at 3000 ms it opens the exit dialog, emits one haptic pulse, and
    // sets _backLongPressFired so the subsequent RELEASE is a no-op.
    function _onBackHoldTick() as Void {
        var now = System.getTimer();
        var held = now - _backHoldStartMs;

        if (held >= 3000) {
            // Threshold reached. Stop the timer, mark the long-press fired.
            if (_backHoldTimer != null) {
                _backHoldTimer.stop();
                _backHoldTimer = null;
            }
            _backLongPressFired = true;
            _backHoldProgress = 0.0;
            WatchUi.requestUpdate();

            // Single haptic pulse (guarded — Attention may be absent on some devices).
            if (Attention has :vibrate) {
                Attention.vibrate([
                    new Attention.VibeProfile(100, 500)
                ]);
            }

            // Push the existing exit confirmation dialog.
            var dialog = new WatchUi.Confirmation(
                WatchUi.loadResource(Rez.Strings.exitConfirmMsg) as String
            );
            WatchUi.pushView(dialog, new ExitConfirmDelegate(_engine), WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        // Still holding — update progress and request a redraw.
        _backHoldProgress = held.toFloat() / 3000.0;
        WatchUi.requestUpdate();
    }

    // Called by WorkoutEngine when the workout transitions to PHASE_FINISHED.
    // Transmits session result to phone, then starts auto-pop timer.
    function _onWorkoutFinished() as Void {
        // Transmit session result to phone
        var resultPayload = _engine.getSessionResultPayload();
        if (resultPayload != null) {
            _commService.sendSetComplete(resultPayload);
        }

        _finishTimer = new Timer.Timer();
        _finishTimer.start(method(:_onFinishTimerExpired), 3000, false);
    }

    // Called 3 seconds after workout completion. Pops the dashboard to reveal
    // the workout summary menu beneath it.
    function _onFinishTimerExpired() as Void {
        _finishTimer = null;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

}
