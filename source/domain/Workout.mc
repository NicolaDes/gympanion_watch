import Toybox.Lang;

class Workout {

    var id as String;
    var name as String;
    var blocks as Array;       // Array<WorkoutBlock>
    var exercises as Array;    // Flattened exercise list for v1 compat / summary menu

    function initialize(id as String, name as String, blocks as Array, exercises as Array) {
        self.id = id;
        self.name = name;
        self.blocks = blocks;
        self.exercises = exercises;
    }

}
