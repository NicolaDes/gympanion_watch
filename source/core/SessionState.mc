import Toybox.Lang;
import Toybox.Time;

// Phase constants defined at module scope so any file can use them
// without needing an instance of SessionState.
const PHASE_IDLE     = 0;
const PHASE_WORK     = 1;
const PHASE_REST     = 2;
const PHASE_FINISHED = 3;

class SessionState {

    var sessionId as String;
    var workoutId as String;
    var currentExerciseIndex as Number;
    var currentSetIndex as Number;
    var phase as Number;
    var timerValueMs as Number;
    var restDurationMs as Number;
    var completedSets as Array;
    var lastWeight as Float;
    var lastReps as Number;
    var startTimestamp as Number;
    var restAlertFired as Boolean;

    function initialize(sessionId as String, workoutId as String) {
        self.sessionId = sessionId;
        self.workoutId = workoutId;
        self.currentExerciseIndex = 0;
        self.currentSetIndex = 0;
        self.phase = PHASE_IDLE;
        self.timerValueMs = 0;
        self.restDurationMs = 0;
        self.completedSets = new [0];
        self.lastWeight = 0.0f;
        self.lastReps = 0;
        self.startTimestamp = Time.now().value();
        self.restAlertFired = false;
    }

    // Serialize to a Dictionary for Application.Storage
    function toDict() as Dictionary {
        var setsArray = new [0];
        for (var i = 0; i < self.completedSets.size(); i++) {
            setsArray.add(self.completedSets[i]);
        }
        return {
            "sid" => self.sessionId,
            "wid" => self.workoutId,
            "eix" => self.currentExerciseIndex,
            "six" => self.currentSetIndex,
            "pha" => self.phase,
            "tmr" => self.timerValueMs,
            "rdr" => self.restDurationMs,
            "cst" => setsArray,
            "lw"  => self.lastWeight,
            "lr"  => self.lastReps,
            "sts" => self.startTimestamp
        };
    }

    // Deserialize from a Dictionary loaded from Application.Storage
    static function fromDict(dict as Dictionary) as SessionState {
        var sid = dict["sid"];
        var wid = dict["wid"];
        if (sid == null) { sid = "restored"; }
        if (wid == null) { wid = ""; }

        var state = new SessionState(sid.toString(), wid.toString());

        var eix = dict["eix"];
        var six = dict["six"];
        var pha = dict["pha"];
        var tmr = dict["tmr"];
        var rdr = dict["rdr"];
        var cst = dict["cst"];
        var lw  = dict["lw"];
        var lr  = dict["lr"];
        var sts = dict["sts"];

        if (eix != null) { state.currentExerciseIndex = eix; }
        if (six != null) { state.currentSetIndex = six; }
        if (pha != null) { state.phase = pha; }
        if (tmr != null) { state.timerValueMs = tmr; }
        if (rdr != null) { state.restDurationMs = rdr; }
        if (lw  != null) { state.lastWeight = lw.toFloat(); }
        if (lr  != null) { state.lastReps = lr; }
        if (sts != null) { state.startTimestamp = sts; }

        if (cst != null && cst instanceof Array) {
            var arr = cst as Array;
            for (var i = 0; i < arr.size(); i++) {
                var entry = arr[i];
                if (entry != null) {
                    state.completedSets.add(entry);
                }
            }
        }

        return state;
    }

}
