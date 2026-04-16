import Toybox.Lang;
import Toybox.Time;

// AMRAP strategy: manages exercise cycling within an AMRAP block.
// A single countdown timer runs from timeCapSec to 0.
// The user presses START to mark each exercise done, cycling through the template.
// When all exercises are completed, a round is counted and the cycle restarts.
//
// nextAction() advances to the next exercise in the template, or wraps to
// round+1 if the template is complete.
class AmrapStrategy extends TimelineStrategy {

    function initialize() {
        TimelineStrategy.initialize();
    }

    // Called when the user presses START to mark the current exercise done.
    // Advances to next exercise in template; wraps to next round if at end.
    //
    // "finished" is never set true here — the timer expiry in WorkoutEngine
    // determines when the AMRAP block ends.
    function nextAction(sessionState as SessionState, workout as Workout) as Dictionary {
        var blocks = workout.blocks;
        if (blocks == null || sessionState.currentBlockIndex >= blocks.size()) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var block = blocks[sessionState.currentBlockIndex] as WorkoutBlock;
        if (block.type != BLOCK_AMRAP || block.sets == null) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var sets = block.sets;
        var setIndex = sessionState.currentSetIndex + 1;

        if (setIndex >= sets.size()) {
            // Template complete — new round
            return {
                "exerciseIndex" => sessionState.currentExerciseIndex,
                "setIndex"      => 0,
                "finished"      => false,
                "roundComplete" => true
            };
        }

        return {
            "exerciseIndex" => sessionState.currentExerciseIndex,
            "setIndex"      => setIndex,
            "finished"      => false,
            "roundComplete" => false
        };
    }

    // Returns the current BlockSet for the active exercise in the AMRAP template.
    function getCurrentBlockSet(sessionState as SessionState, workout as Workout) as BlockSet or Null {
        var blocks = workout.blocks;
        if (blocks == null || sessionState.currentBlockIndex >= blocks.size()) { return null; }

        var block = blocks[sessionState.currentBlockIndex] as WorkoutBlock;
        if (block.type != BLOCK_AMRAP || block.sets == null) { return null; }

        var si = sessionState.currentSetIndex;
        if (si >= block.sets.size()) { return null; }

        return block.sets[si] as BlockSet;
    }

    // Computes remaining seconds for the AMRAP block.
    // timeCapSec - (now - blockStartTimestamp)
    function getTotalRemainingSec(sessionState as SessionState, block as WorkoutBlock) as Number {
        if (block.timeCapSec == null) { return 0; }
        var elapsed = Time.now().value() - sessionState.blockStartTimestamp;
        var remaining = block.timeCapSec - elapsed;
        return remaining > 0 ? remaining : 0;
    }

}
