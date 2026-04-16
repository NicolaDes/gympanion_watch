import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Timer;

// DashboardDelegate: handles all button input on the main workout dashboard.
// Phase-aware routing: the same START button does different things
// depending on the current workout phase.
class DashboardDelegate extends WatchUi.BehaviorDelegate {

    private var _engine      as WorkoutEngine;
    private var _commService as CompanionCommService;
    private var _finishTimer as Timer.Timer or Null;

    function initialize(engine as WorkoutEngine, commService as CompanionCommService) {
        BehaviorDelegate.initialize();
        _engine      = engine;
        _commService = commService;
        _finishTimer = null;
        _engine.setOnFinished(method(:_onWorkoutFinished));
    }

    // START/STOP button. Behavior depends on phase and block type.
    function onSelect() as Boolean {
        var state = _engine.getCurrentState();
        if (state == null) { return true; }

        var phase = state.phase;

        // IDLE or BLOCK_COMPLETE: start the (next) block
        if (phase == PHASE_IDLE || phase == PHASE_BLOCK_COMPLETE) {
            _engine.startSet();
            return true;
        }

        // REST during sequential: cut rest short, start next set
        if (phase == PHASE_REST) {
            var block = _engine.getCurrentBlock();
            if (block != null && block.type == BLOCK_SEQUENTIAL) {
                _engine.startSet();
            }
            // EMOM REST: user can't skip the interval — do nothing
            return true;
        }

        // WORK phase: mark current exercise/set done
        if (phase == PHASE_WORK) {
            var block = _engine.getCurrentBlock();
            if (block == null) { return true; }

            var targetWeight = _engine.getCurrentTargetWeight();
            var targetReps   = _engine.getCurrentTargetReps();
            var exerciseName = _engine.getCurrentExerciseName();

            // Build phone notification payload
            var workout = _engine.getWorkout();
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
        }

        return true;
    }

    // BACK button: always shows an exit confirmation dialog.
    // Yes -> persists session and exits the app.
    // No  -> dialog is dismissed by the system; returns to dashboard.
    function onBack() as Boolean {
        var dialog = new WatchUi.Confirmation(
            WatchUi.loadResource(Rez.Strings.exitConfirmMsg) as String
        );
        WatchUi.pushView(dialog, new ExitConfirmDelegate(_engine), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    // Long-press UP. Reserved for future menu use. No-op in skeleton.
    function onMenu() as Boolean {
        return true;
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
