import Toybox.Lang;

class ExerciseSet {

    var exerciseIndex as Number;
    var setIndex as Number;
    var weight as Float;
    var reps as Number;
    var avgHeartRate as Number or Null;
    var timestamp as Number;

    function initialize(
        exerciseIndex as Number,
        setIndex as Number,
        weight as Float,
        reps as Number,
        avgHeartRate as Number or Null,
        timestamp as Number
    ) {
        self.exerciseIndex = exerciseIndex;
        self.setIndex = setIndex;
        self.weight = weight;
        self.reps = reps;
        self.avgHeartRate = avgHeartRate;
        self.timestamp = timestamp;
    }

}
