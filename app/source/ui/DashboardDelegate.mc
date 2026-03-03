import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// DashboardDelegate: handles all button input on the main workout dashboard.
// Phase-aware routing: the same START button does different things
// depending on the current workout phase.
class DashboardDelegate extends WatchUi.BehaviorDelegate {

    private var _engine as WorkoutEngine;

    function initialize(engine as WorkoutEngine) {
        BehaviorDelegate.initialize();
        _engine = engine;
    }

    // START/STOP button. Behavior depends on current phase:
    //   IDLE     -> start set (begin work phase)
    //   WORK     -> done with set; push SetEditView to confirm weight/reps
    //   REST     -> start next set early (user cuts rest short)
    //   FINISHED -> no action
    function onSelect() as Boolean {
        var state = _engine.getCurrentState();
        if (state == null) { return true; }

        var phase = state.phase;

        if (phase == PHASE_IDLE || phase == PHASE_REST) {
            _engine.startSet();
        } else if (phase == PHASE_WORK) {
            // Pause timer and push set-edit screen
            _engine.pause();
            var workout = _engine.getWorkout();
            var exercise = null;
            if (workout != null && workout.exercises != null) {
                var exIndex = state.currentExerciseIndex;
                if (exIndex < workout.exercises.size()) {
                    exercise = workout.exercises[exIndex] as Exercise;
                }
            }

            // Default weight/reps: last-used values, or exercise targets if first set
            var defaultWeight = state.lastWeight;
            var defaultReps   = state.lastReps;
            if (defaultWeight <= 0.0f && exercise != null) {
                defaultWeight = exercise.targetWeight;
            }
            if (defaultReps <= 0 && exercise != null) {
                defaultReps = exercise.targetReps;
            }

            var editView     = new SetEditView(_engine, defaultWeight, defaultReps);
            var editDelegate = new SetEditDelegate(_engine, editView);
            WatchUi.pushView(editView, editDelegate, WatchUi.SLIDE_UP);
        }
        // PHASE_FINISHED: no action
        return true;
    }

    // BACK button.
    //   IDLE / FINISHED -> clear saved session and start a fresh one (stay in app)
    //   WORK / REST     -> swallowed to prevent accidental exit mid-workout
    function onBack() as Boolean {
        var state = _engine.getCurrentState();
        if (state == null) {
            _engine.resetSession();
            return true;
        }

        var phase = state.phase;
        if (phase == PHASE_IDLE || phase == PHASE_FINISHED) {
            _engine.resetSession();
        }
        // During WORK or REST: swallow to prevent accidental exit
        return true;
    }

    // Long-press UP. Reserved for future menu use. No-op in skeleton.
    function onMenu() as Boolean {
        return true;
    }

}
