import Toybox.Lang;
import Toybox.Sensor;

// Real implementation of PhysiologicalProvider that reads HR from the
// device's hardware sensor via Toybox.Sensor.getInfo().
// Requires the "Sensor" permission in manifest.xml (already declared).
class RealPhysiologicalProvider extends PhysiologicalProvider {

    function initialize() {
        PhysiologicalProvider.initialize();
    }

    function getHeartRate() as Number or Null {
        if (!(Toybox has :Sensor)) { return null; }
        var info = Sensor.getInfo();
        if (info == null) { return null; }
        if (!(info has :heartRate)) { return null; }
        return info.heartRate;
    }

    function getCalories() as Number or Null {
        return null;
    }

}
