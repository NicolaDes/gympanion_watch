import Toybox.Lang;
import Toybox.Time;

// EMOM strategy: manages round progression within an EMOM block.
// Each round has an interval (e.g., 60s). Exercises rotate per round.
// The strategy tracks which round and which set within the round is active.
//
// nextAction() is called after the user marks an exercise done within a round.
// It advances to the next set in the round (if multi-exercise), or stays
// on the current round until the interval timer expires.
//
// The interval expiry and round auto-advance is handled by WorkoutEngine's
// tick handler, not by nextAction().
class EmomStrategy extends TimelineStrategy {

    function initialize() {
        TimelineStrategy.initialize();
    }

    // Called when the user presses START to mark the current exercise done.
    // Advances to the next set within the current round if there are more.
    // Does NOT advance rounds — that's timer-driven.
    //
    // Returns:
    //   "setIndex"      => next set index within the round
    //   "roundFinished" => true if all sets in this round are done
    //   "finished"      => true if all rounds are complete (total time reached)
    function nextAction(sessionState as SessionState, workout as Workout) as Dictionary {
        var blocks = workout.blocks;
        if (blocks == null || sessionState.currentBlockIndex >= blocks.size()) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var block = blocks[sessionState.currentBlockIndex] as WorkoutBlock;
        if (block.type != BLOCK_EMOM || block.rounds == null) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var rounds = block.rounds;
        var roundIndex = sessionState.currentRoundIndex;

        // Guard: if we're past the last round, block is done
        if (roundIndex >= rounds.size()) {
            return { "exerciseIndex" => 0, "setIndex" => 0, "finished" => true };
        }

        var currentRound = rounds[roundIndex] as EmomRound;
        var setIndex = sessionState.currentSetIndex + 1;

        // If more sets in this round, advance set
        if (setIndex < currentRound.sets.size()) {
            return {
                "exerciseIndex" => sessionState.currentExerciseIndex,
                "setIndex"      => setIndex,
                "finished"      => false,
                "roundFinished" => false
            };
        }

        // All sets in this round are done — round is finished
        // (round advancement happens on timer tick, not here)
        return {
            "exerciseIndex" => sessionState.currentExerciseIndex,
            "setIndex"      => setIndex,
            "finished"      => false,
            "roundFinished" => true
        };
    }

    // Returns the current BlockSet for the active round and set index.
    // Used by DashboardView and DashboardDelegate to get exercise name, target reps, etc.
    function getCurrentBlockSet(sessionState as SessionState, workout as Workout) as BlockSet or Null {
        var blocks = workout.blocks;
        if (blocks == null || sessionState.currentBlockIndex >= blocks.size()) { return null; }

        var block = blocks[sessionState.currentBlockIndex] as WorkoutBlock;
        if (block.type != BLOCK_EMOM || block.rounds == null) { return null; }

        var rounds = block.rounds;
        var ri = sessionState.currentRoundIndex;
        if (ri >= rounds.size()) { return null; }

        var round = rounds[ri] as EmomRound;
        var si = sessionState.currentSetIndex;
        if (si >= round.sets.size()) { return null; }

        return round.sets[si] as BlockSet;
    }

    // Computes total block duration in seconds: intervalSec * number of rounds
    function getTotalDurationSec(block as WorkoutBlock) as Number {
        if (block.intervalSec == null || block.rounds == null) { return 0; }
        return block.intervalSec * block.rounds.size();
    }

    // Computes remaining seconds in the current interval.
    // intervalSec - (now - roundStartTimestamp)
    function getIntervalRemainingSec(sessionState as SessionState, block as WorkoutBlock) as Number {
        if (block.intervalSec == null) { return 0; }
        var elapsed = Time.now().value() - sessionState.roundStartTimestamp;
        var remaining = block.intervalSec - elapsed;
        return remaining > 0 ? remaining : 0;
    }

    // Computes total remaining seconds for the entire EMOM block.
    // totalDuration - (now - blockStartTimestamp)
    function getTotalRemainingSec(sessionState as SessionState, block as WorkoutBlock) as Number {
        var total = getTotalDurationSec(block);
        var elapsed = Time.now().value() - sessionState.blockStartTimestamp;
        var remaining = total - elapsed;
        return remaining > 0 ? remaining : 0;
    }

}
