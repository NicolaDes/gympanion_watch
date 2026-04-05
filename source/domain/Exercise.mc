import Toybox.Lang;

class Exercise {

    var id as String;
    var name as String;
    var targetSets as Number;
    var targetReps as Number;
    var targetWeight as Float;
    var restDurationSec as Number;
    var sets as Array or Null;   // Array<BlockSet> — v2 per-set params, null for v1

    function initialize(
        name as String,
        targetSets as Number,
        targetReps as Number,
        targetWeight as Float,
        restDurationSec as Number
    ) {
        self.id = "";
        self.name = name;
        self.targetSets = targetSets;
        self.targetReps = targetReps;
        self.targetWeight = targetWeight;
        self.restDurationSec = restDurationSec;
        self.sets = null;
    }

    // v2 constructor: exercise with per-set BlockSet array
    static function fromBlockSets(id as String, name as String, blockSets as Array) as Exercise {
        var ex = new Exercise(name, blockSets.size(), 0, 0.0f, 0);
        ex.id = id;
        ex.sets = blockSets;
        // Set targetReps/targetWeight from first set for display defaults
        if (blockSets.size() > 0) {
            var first = blockSets[0] as BlockSet;
            if (first.reps != null) { ex.targetReps = first.reps; }
            if (first.wKg != null) { ex.targetWeight = first.wKg; }
            if (first.restSec != null) { ex.restDurationSec = first.restSec; }
        }
        return ex;
    }

}
