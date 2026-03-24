import Toybox.Lang;

class Exercise {

    var name as String;
    var targetSets as Number;
    var targetReps as Number;
    var targetWeight as Float;
    var restDurationSec as Number;

    function initialize(
        name as String,
        targetSets as Number,
        targetReps as Number,
        targetWeight as Float,
        restDurationSec as Number
    ) {
        self.name = name;
        self.targetSets = targetSets;
        self.targetReps = targetReps;
        self.targetWeight = targetWeight;
        self.restDurationSec = restDurationSec;
    }

}
