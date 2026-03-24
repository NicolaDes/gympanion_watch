import Toybox.Lang;

// Factory class that provides the hardcoded default workout for the skeleton.
// Future versions will load workouts from storage or a companion app.
class StaticWorkoutLoader {

    function initialize() {
    }

    // Returns the default three-exercise workout:
    //   Bench Press: 4x10 at 60kg, 90s rest
    //   Squat:       4x8  at 80kg, 120s rest
    //   Deadlift:    3x5  at 100kg, 150s rest
    static function loadDefaultWorkout() as Workout {
        var exercises = [
            new Exercise("Bench Press", 4, 10, 60.0f, 90),
            new Exercise("Squat",       4, 8,  80.0f, 120),
            new Exercise("Deadlift",    3, 5,  100.0f, 150)
        ];
        return new Workout("default_workout", "Default Workout", exercises);
    }

}
