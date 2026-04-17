import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// Builds and transmits a live workout status snapshot to the companion phone app.
// Fire-and-forget via Communications.transmit() — same pattern as sendSetComplete().
// Payload type is "liveStatus", consumed by iOS GarminPayloadDecoder.
class LiveStatusTransmitter {

    private var _listener as NoOpConnectionListener;
    private var _provider as PhysiologicalProvider;

    function initialize(provider as PhysiologicalProvider) {
        _listener = new NoOpConnectionListener();
        _provider = provider;
    }

    // Builds and transmits a liveStatus payload. Safe to call at any time —
    // silently no-ops if transmit is unavailable or phone is not connected.
    function send(state as SessionState, workout as Workout) as Void {
        if (!(Communications has :transmit)) {
            System.println("[LiveStatus] transmit not available");
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            System.println("[LiveStatus] No phone connected, skipping");
            return;
        }

        var payload = _buildPayload(state, workout);
        try {
            Communications.transmit(payload, null, _listener);
            System.println("[LiveStatus] Sent: phase=" + state.phase.toString()
                + " ex=" + state.currentExerciseIndex.toString());
        } catch (e instanceof Lang.Exception) {
            System.println("[LiveStatus] transmit failed: " + e.getErrorMessage());
        }
    }

    // Assembles the payload dictionary from current session state and workout.
    private function _buildPayload(state as SessionState, workout as Workout) as Dictionary {
        // Compute completed reps total
        var completedReps = 0;
        for (var i = 0; i < state.completedSets.size(); i++) {
            var rec = state.completedSets[i] as Dictionary;
            var r = rec["r"];
            if (r != null) {
                completedReps = completedReps + r;
            }
        }

        // Get point-in-time heart rate
        var hr = _provider.getHeartRate();

        // Build flattened exercise summary array from workout
        var exerciseSummary = _buildExerciseSummary(workout);

        return {
            "type"                 => "liveStatus",
            "exerciseName"         => _resolveExerciseName(state, workout),
            "currentExerciseIndex" => state.currentExerciseIndex,
            "currentSetIndex"      => state.currentSetIndex,
            "completedSets"        => state.completedSets.size(),
            "completedReps"        => completedReps,
            "heartRate"            => hr != null ? hr : -1,
            "phase"                => state.phase,
            "workout"              => {
                "id"        => workout.id,
                "name"      => workout.name,
                "exercises" => exerciseSummary
            }
        };
    }

    // Resolves the current exercise name from state + workout.
    // For sequential blocks: uses block.exercises[exIdx].name
    // For EMOM/AMRAP: uses the block's sets/rounds to find the current exercise.
    private function _resolveExerciseName(state as SessionState, workout as Workout) as String {
        if (workout.blocks == null) { return "---"; }
        var blocks = workout.blocks;
        if (state.currentBlockIndex >= blocks.size()) { return "---"; }

        var block = blocks[state.currentBlockIndex] as WorkoutBlock;

        if (block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
            var exIdx = state.currentExerciseIndex;
            if (exIdx < block.exercises.size()) {
                var ex = block.exercises[exIdx] as Exercise;
                return ex.name;
            }
        } else if (block.type == BLOCK_EMOM && block.rounds != null) {
            var rounds = block.rounds;
            var ri = state.currentRoundIndex;
            if (ri < rounds.size()) {
                var round = rounds[ri] as EmomRound;
                var si = state.currentSetIndex;
                if (round.sets != null && si < round.sets.size()) {
                    var bs = round.sets[si] as BlockSet;
                    return bs.name;
                }
            }
        } else if (block.type == BLOCK_AMRAP && block.sets != null) {
            var si = state.currentSetIndex;
            if (si < block.sets.size()) {
                var bs = block.sets[si] as BlockSet;
                return bs.name;
            }
        }

        return "---";
    }

    // Builds a flattened exercise summary array from all blocks in the workout.
    // Each entry: { "name" => String, "targetSets" => Number, "targetReps" => Number }
    private function _buildExerciseSummary(workout as Workout) as Array {
        var result = new [0];
        if (workout.blocks == null) { return result; }

        var blocks = workout.blocks;
        for (var bi = 0; bi < blocks.size(); bi++) {
            var block = blocks[bi] as WorkoutBlock;

            if (block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
                var exercises = block.exercises;
                for (var ei = 0; ei < exercises.size(); ei++) {
                    var ex = exercises[ei] as Exercise;
                    result.add({
                        "name"       => ex.name,
                        "targetSets" => ex.targetSets,
                        "targetReps" => ex.targetReps
                    });
                }
            } else if (block.type == BLOCK_EMOM && block.rounds != null) {
                // Use first round as template — all rounds have the same exercises
                var rounds = block.rounds;
                if (rounds.size() > 0) {
                    var firstRound = rounds[0] as EmomRound;
                    if (firstRound.sets != null) {
                        var sets = firstRound.sets;
                        for (var si = 0; si < sets.size(); si++) {
                            var bs = sets[si] as BlockSet;
                            result.add({
                                "name"       => bs.name,
                                "targetSets" => rounds.size(),
                                "targetReps" => bs.reps != null ? bs.reps : 0
                            });
                        }
                    }
                }
            } else if (block.type == BLOCK_AMRAP && block.sets != null) {
                var sets = block.sets;
                for (var si = 0; si < sets.size(); si++) {
                    var bs = sets[si] as BlockSet;
                    result.add({
                        "name"       => bs.name,
                        "targetSets" => 0,
                        "targetReps" => bs.reps != null ? bs.reps : 0
                    });
                }
            }
        }

        return result;
    }

}
