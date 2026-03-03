import Toybox.Lang;

class MetricSnapshot {

    var timestamp as Number;
    var heartRate as Number or Null;
    var calories as Number or Null;
    var respiration as Number or Null;
    var stress as Number or Null;

    function initialize(
        timestamp as Number,
        heartRate as Number or Null,
        calories as Number or Null,
        respiration as Number or Null,
        stress as Number or Null
    ) {
        self.timestamp = timestamp;
        self.heartRate = heartRate;
        self.calories = calories;
        self.respiration = respiration;
        self.stress = stress;
    }

}
