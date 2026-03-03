import Toybox.Lang;

// Sequential workout strategy: completes all sets of each exercise in order,
// then advances to the next exercise. Finishes when all exercises are done.
class SequentialStrategy extends TimelineStrategy {

    function initialize() {
        TimelineStrategy.initialize();
    }

    // Computes the next exercise and set indices after the current set is completed.
    function nextAction(sessionState as SessionState, workout as Workout) as Dictionary {
        var exerciseIndex = sessionState.currentExerciseIndex;
        var setIndex      = sessionState.currentSetIndex;

        var exercises = workout.exercises;
        if (exercises == null || exercises.size() == 0) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var currentExercise = exercises[exerciseIndex] as Exercise;

        // Advance to the next set
        setIndex = setIndex + 1;

        // Check if all sets of the current exercise are done
        if (setIndex >= currentExercise.targetSets) {
            setIndex = 0;
            exerciseIndex = exerciseIndex + 1;
        }

        // Check if all exercises are done
        if (exerciseIndex >= exercises.size()) {
            return {
                "exerciseIndex" => exerciseIndex,
                "setIndex"      => setIndex,
                "finished"      => true
            };
        }

        return {
            "exerciseIndex" => exerciseIndex,
            "setIndex"      => setIndex,
            "finished"      => false
        };
    }

}
