import Toybox.Lang;

// Base class for workout mode strategies.
// Subclasses override nextAction() to implement mode-specific progression.
class TimelineStrategy {

    function initialize() {
    }

    // Returns a Dictionary: { "exerciseIndex" => Number, "setIndex" => Number, "finished" => Boolean }
    // Base implementation always returns finished = true.
    // Subclasses must override this method.
    function nextAction(sessionState as SessionState, workout as Workout) as Dictionary {
        return {
            "exerciseIndex" => sessionState.currentExerciseIndex,
            "setIndex"      => sessionState.currentSetIndex,
            "finished"      => true
        };
    }

}
