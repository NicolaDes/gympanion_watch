import Toybox.Lang;

class Workout {

    var id as String;
    var name as String;
    var exercises as Array;

    function initialize(id as String, name as String, exercises as Array) {
        self.id = id;
        self.name = name;
        self.exercises = exercises;
    }

}
