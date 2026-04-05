import Toybox.Lang;

class BlockSet {

    var exId as String;
    var name as String;
    var si as Number;
    var reps as Number or Null;
    var wKg as Float or Null;
    var durSec as Number or Null;
    var distM as Float or Null;
    var restSec as Number or Null;

    function initialize(
        exId as String,
        name as String,
        si as Number,
        reps as Number or Null,
        wKg as Float or Null,
        durSec as Number or Null,
        distM as Float or Null,
        restSec as Number or Null
    ) {
        self.exId = exId;
        self.name = name;
        self.si = si;
        self.reps = reps;
        self.wKg = wKg;
        self.durSec = durSec;
        self.distM = distM;
        self.restSec = restSec;
    }

}
