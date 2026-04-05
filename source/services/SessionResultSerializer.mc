import Toybox.Lang;
import Toybox.Time;
import Toybox.System;

class SessionResultSerializer {

    function initialize() {
    }

    function serialize(state as SessionState, workout as Workout) as Dictionary {
        var nowTs = Time.now().value();
        var totalDurationSec = nowTs - state.startTimestamp;

        var deviceId = "";
        var settings = System.getDeviceSettings();
        if (settings has :uniqueIdentifier && settings.uniqueIdentifier != null) {
            deviceId = settings.uniqueIdentifier;
        }

        return {
            "v"               => 2,
            "type"            => "session_result",
            "workoutId"       => state.workoutId,
            "sessionId"       => state.sessionId,
            "deviceId"        => deviceId,
            "startedAt"       => state.startTimestamp,
            "completedAt"     => nowTs,
            "totalDurationSec" => totalDurationSec,
            "blocks"          => state.blockResults
        };
    }

    // Builds a sequential block result from completed sets.
    // completedSets: array of set-result dictionaries recorded during execution.
    // exercises: the Exercise objects from the block, used to group sets by exercise.
    function serializeSequentialBlockResult(
        blockIndex as Number,
        exercises as Array,
        completedSets as Array
    ) as Dictionary {
        var exerciseResults = new [0];

        for (var i = 0; i < exercises.size(); i++) {
            var ex = exercises[i] as Exercise;
            var exSets = new [0];

            for (var j = 0; j < completedSets.size(); j++) {
                var setRec = completedSets[j] as Dictionary;
                if (setRec["ei"] == i) {
                    exSets.add({
                        "si"          => setRec["si"],
                        "reps"        => setRec["r"],
                        "wKg"         => setRec["w"],
                        "durMs"       => setRec["durMs"],
                        "avgHr"       => setRec["hr"],
                        "peakHr"      => setRec["peakHr"],
                        "completedAt" => setRec["ts"]
                    });
                }
            }

            exerciseResults.add({
                "exId" => ex.id,
                "sets" => exSets
            });
        }

        return {
            "bi"        => blockIndex,
            "type"      => "sequential",
            "exercises" => exerciseResults
        };
    }

    function serializeEmomBlockResult(
        blockIndex as Number,
        intervalSec as Number,
        roundResults as Array  // Array of { "ri" => N, "ttc" => N, "trem" => N, "sets" => Array }
    ) as Dictionary {
        var rounds = new [0];

        for (var i = 0; i < roundResults.size(); i++) {
            var rr = roundResults[i] as Dictionary;
            rounds.add({
                "ri"                => rr["ri"],
                "timeToCompleteSec" => rr["ttc"],
                "timeRemainingSec"  => rr["trem"],
                "sets"              => rr["sets"]
            });
        }

        return {
            "bi"          => blockIndex,
            "type"        => "emom",
            "intervalSec" => intervalSec,
            "rounds"      => rounds
        };
    }

    function serializeAmrapBlockResult(
        blockIndex as Number,
        timeCapSec as Number,
        roundsCompleted as Number,
        partialReps as Number,
        roundResults as Array  // Array of { "ri" => N, "durMs" => N, "partial" => Bool, "sets" => Array }
    ) as Dictionary {
        var rounds = new [0];

        for (var i = 0; i < roundResults.size(); i++) {
            var rr = roundResults[i] as Dictionary;
            var roundDict = {
                "ri"    => rr["ri"],
                "durMs" => rr["durMs"],
                "sets"  => rr["sets"]
            };
            var isPartial = rr["partial"];
            if (isPartial != null && isPartial == true) {
                roundDict.put("partial", true);
            }
            rounds.add(roundDict);
        }

        return {
            "bi"              => blockIndex,
            "type"            => "amrap",
            "timeCapSec"      => timeCapSec,
            "roundsCompleted" => roundsCompleted,
            "partialReps"     => partialReps,
            "rounds"          => rounds
        };
    }

}
