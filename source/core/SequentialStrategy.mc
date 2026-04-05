import Toybox.Lang;

// Sequential workout strategy: completes all sets of each exercise in order,
// then advances to the next exercise. Finishes when all exercises are done.
// Supports both v1 (uniform targetSets) and v2 (per-set BlockSet arrays).
class SequentialStrategy extends TimelineStrategy {

    function initialize() {
        TimelineStrategy.initialize();
    }

    // Computes the next exercise and set indices after the current set is completed.
    function nextAction(sessionState as SessionState, workout as Workout) as Dictionary {
        var exerciseIndex = sessionState.currentExerciseIndex;
        var setIndex      = sessionState.currentSetIndex;

        // Get exercises from current block
        var block = null;
        var blocks = workout.blocks;
        if (blocks != null && sessionState.currentBlockIndex < blocks.size()) {
            block = blocks[sessionState.currentBlockIndex] as WorkoutBlock;
        }

        var exercises;
        if (block != null && block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
            exercises = block.exercises;
        } else {
            exercises = workout.exercises;
        }

        if (exercises == null || exercises.size() == 0) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var currentExercise = exercises[exerciseIndex] as Exercise;
        setIndex = setIndex + 1;

        // Determine total sets: use BlockSet array size if available, else targetSets
        var totalSets = currentExercise.targetSets;
        if (currentExercise.sets != null) {
            totalSets = currentExercise.sets.size();
        }

        if (setIndex >= totalSets) {
            setIndex = 0;
            exerciseIndex = exerciseIndex + 1;
        }

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
