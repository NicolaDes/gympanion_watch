import Toybox.Lang;

// Block type constants
const BLOCK_SEQUENTIAL = 0;
const BLOCK_EMOM       = 1;
const BLOCK_AMRAP      = 2;

class WorkoutBlock {

    var type as Number;        // BLOCK_SEQUENTIAL | BLOCK_EMOM | BLOCK_AMRAP
    var name as String;

    // Sequential: array of Exercise objects (each with optional BlockSet array)
    var exercises as Array or Null;

    // EMOM
    var intervalSec as Number or Null;
    var rounds as Array or Null;   // Array<EmomRound>

    // AMRAP
    var timeCapSec as Number or Null;
    var sets as Array or Null;     // Array<BlockSet> (one round template)

    function initialize(type as Number, name as String) {
        self.type = type;
        self.name = name;
        self.exercises = null;
        self.intervalSec = null;
        self.rounds = null;
        self.timeCapSec = null;
        self.sets = null;
    }

}
