import Toybox.Lang;
import Toybox.Math;

// Mock implementation of PhysiologicalProvider that returns randomized but
// plausible physiological values for use in the simulator.
class MockPhysiologicalProvider extends PhysiologicalProvider {

    private var _heartRate  as Number;
    private var _calories   as Float;

    function initialize() {
        PhysiologicalProvider.initialize();
        _heartRate = 70;
        _calories  = 0.0f;
    }

    function getHeartRate() as Number or Null {
        // Trend upward slightly each call (simulates exertion)
        var delta = Math.rand() % 4; // 0-3
        _heartRate = _heartRate + delta - 1; // net: -1 to +2
        if (_heartRate < 55)  { _heartRate = 55; }
        if (_heartRate > 180) { _heartRate = 180; }
        return _heartRate;
    }

    function getCalories() as Number or Null {
        // Increment by ~0.1-0.3 per second (approximation)
        _calories = _calories + 0.2f;
        return _calories.toNumber();
    }

    function getRespiration() as Number or Null {
        return null;
    }

    function getStress() as Number or Null {
        return null;
    }

}
