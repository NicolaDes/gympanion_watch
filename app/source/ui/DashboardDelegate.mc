import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// DashboardDelegate: handles all button input on the main workout dashboard.
// Phase-aware routing: the same START button does different things
// depending on the current workout phase.
class DashboardDelegate extends WatchUi.BehaviorDelegate {

    private var _engine      as WorkoutEngine;
    private var _commService as CompanionCommService;

    function initialize(engine as WorkoutEngine, commService as CompanionCommService) {
        BehaviorDelegate.initialize();
        _engine      = engine;
        _commService = commService;
    }

    // START/STOP button. Behavior depends on current phase:
    //   IDLE     -> start set (begin work phase)
    //   WORK     -> set complete: auto-record with target values, notify phone, transition to REST
    //   REST     -> start next set early (user cuts rest short)
    //   FINISHED -> no action
    function onSelect() as Boolean {
        var state = _engine.getCurrentState();
        if (state == null) { return true; }

        var phase = state.phase;

        if (phase == PHASE_IDLE || phase == PHASE_REST) {
            _engine.startSet();
        } else if (phase == PHASE_WORK) {
            // Resolve the current exercise to get target weight/reps
            var workout = _engine.getWorkout();
            var exercise = null;
            if (workout != null && workout.exercises != null) {
                var exIndex = state.currentExerciseIndex;
                if (exIndex < workout.exercises.size()) {
                    exercise = workout.exercises[exIndex] as Exercise;
                }
            }

            // Use target values from the exercise definition; default to 0 if unavailable
            var targetWeight = 0.0f;
            var targetReps   = 0;
            var exerciseName = "";
            var totalSets    = 0;
            var totalExercises = (workout != null && workout.exercises != null)
                ? workout.exercises.size()
                : 0;

            if (exercise != null) {
                targetWeight  = exercise.targetWeight;
                targetReps    = exercise.targetReps;
                exerciseName  = exercise.name;
                totalSets     = exercise.targetSets;
            }

            // Build fire-and-forget phone notification payload
            var payload = {
                "type"           => "set_complete",
                "exerciseName"   => exerciseName,
                "exerciseIndex"  => state.currentExerciseIndex,
                "totalExercises" => totalExercises,
                "setIndex"       => state.currentSetIndex,
                "totalSets"      => totalSets,
                "durationMs"     => state.timerValueMs,
                "targetWeight"   => targetWeight,
                "targetReps"     => targetReps
            };

            _commService.sendSetComplete(payload);
            _engine.completeSet(targetWeight, targetReps);
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
