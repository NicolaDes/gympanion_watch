import Toybox.Lang;

// Base class (interface) for physiological data providers.
// Subclasses provide real sensor data or mock data for testing.
class PhysiologicalProvider {

    function initialize() {
    }

    // Returns the current heart rate in BPM, or null if unavailable.
    function getHeartRate() as Number or Null {
        return null;
    }

    // Returns cumulative calorie count, or null if unavailable.
    function getCalories() as Number or Null {
        return null;
    }

    // Returns current respiration rate, or null if unavailable.
    function getRespiration() as Number or Null {
        return null;
    }

    // Returns current stress level (0-100), or null if unavailable.
    function getStress() as Number or Null {
        return null;
    }

}
