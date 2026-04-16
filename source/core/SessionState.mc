import Toybox.Lang;
import Toybox.Time;

// Phase constants defined at module scope so any file can use them
// without needing an instance of SessionState.
const PHASE_IDLE           = 0;
const PHASE_WORK           = 1;
const PHASE_REST           = 2;
const PHASE_FINISHED       = 3;
const PHASE_BLOCK_COMPLETE = 4;

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

    // Block-aware fields (v2)
    var currentBlockIndex as Number;
    var blockResults as Array;         // Array of result Dictionaries, one per block
    var currentRoundIndex as Number;   // For EMOM: which round; For AMRAP: current round count
    var roundStartTimestamp as Number;  // For EMOM: when the current round started
    var blockStartTimestamp as Number;  // When the current block started
    var amrapRoundsCompleted as Number;
    var amrapPartialReps as Number;

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

        // Block-aware defaults
        self.currentBlockIndex = 0;
        self.blockResults = new [0];
        self.currentRoundIndex = 0;
        self.roundStartTimestamp = 0;
        self.blockStartTimestamp = 0;
        self.amrapRoundsCompleted = 0;
        self.amrapPartialReps = 0;
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
            "sts" => self.startTimestamp,
            "cbi" => self.currentBlockIndex,
            "brs" => self.blockResults,
            "cri" => self.currentRoundIndex,
            "rst" => self.roundStartTimestamp,
            "bst" => self.blockStartTimestamp,
            "arc" => self.amrapRoundsCompleted,
            "apr" => self.amrapPartialReps
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

        // Restore block-aware fields
        var cbi = dict["cbi"];
        var brs = dict["brs"];
        var cri = dict["cri"];
        var rst = dict["rst"];
        var bst = dict["bst"];
        var arc = dict["arc"];
        var apr = dict["apr"];

        if (cbi != null) { state.currentBlockIndex = cbi; }
        if (cri != null) { state.currentRoundIndex = cri; }
        if (rst != null) { state.roundStartTimestamp = rst; }
        if (bst != null) { state.blockStartTimestamp = bst; }
        if (arc != null) { state.amrapRoundsCompleted = arc; }
        if (apr != null) { state.amrapPartialReps = apr; }

        if (brs != null && brs instanceof Array) {
            var arr = brs as Array;
            for (var i = 0; i < arr.size(); i++) {
                if (arr[i] != null) { state.blockResults.add(arr[i]); }
            }
        }

        return state;
    }

}
