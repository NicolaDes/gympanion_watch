import Toybox.Lang;
import Toybox.Time;
import Toybox.System;

// Samples physiological data during a set and computes per-set averages.
// Also emits periodic MetricSampled events to EventRecorder.
class SamplingEngine {

    private var _provider      as PhysiologicalProvider;
    private var _eventRecorder as EventRecorder;
    private var _snapshots     as Array;
    private var _hrSum         as Number;
    private var _hrCount       as Number;
    private var _tickCount     as Number;

    // Emit a MetricSampled event every N ticks (every 5 seconds)
    private const EMIT_INTERVAL = 5;

    function initialize(provider as PhysiologicalProvider, eventRecorder as EventRecorder) {
        _provider      = provider;
        _eventRecorder = eventRecorder;
        _snapshots     = new [0];
        _hrSum         = 0;
        _hrCount       = 0;
        _tickCount     = 0;
    }

    // Clears the accumulator. Call at the start of each set.
    function beginSet() as Void {
        _snapshots = new [0];
        _hrSum     = 0;
        _hrCount   = 0;
        _tickCount = 0;
    }

    // Reads the provider and accumulates one sample. Call on each timer tick.
    function sample() as Void {
        var now = Time.now().value();
        var hr  = _provider.getHeartRate();
        var cal = _provider.getCalories();

        var snapshot = new MetricSnapshot(now, hr, cal, null, null);
        _snapshots.add(snapshot);

        if (hr != null) {
            _hrSum   = _hrSum + hr;
            _hrCount = _hrCount + 1;
        }

        _tickCount = _tickCount + 1;

        // Emit periodic event every EMIT_INTERVAL seconds
        if (_tickCount % EMIT_INTERVAL == 0) {
            _eventRecorder.record("MetricSampled", {
                "heartRate"   => hr != null ? hr : -1,
                "calories"    => cal,
                "respiration" => null,
                "stress"      => null
            });
        }
    }

    // Computes and returns the average heart rate for the current set.
    // Clears the buffer. Returns null if no heart rate data was collected.
    function finalizeSet() as Number or Null {
        if (_hrCount == 0) {
            return null;
        }
        var avg = (_hrSum / _hrCount).toNumber();
        _snapshots = new [0];
        _hrSum     = 0;
        _hrCount   = 0;
        _tickCount = 0;
        return avg;
    }

}
