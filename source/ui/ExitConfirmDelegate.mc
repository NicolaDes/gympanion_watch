import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// ExitConfirmDelegate: handles the yes/no response from the exit confirmation dialog.
// Yes -> persists the session then exits the app.
// No  -> the system already dismissed the overlay; nothing to do.
class ExitConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _engine as WorkoutEngine;

    function initialize(engine as WorkoutEngine) {
        ConfirmationDelegate.initialize();
        _engine = engine;
    }

    function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) {
            _engine.pause(); // persist session before exit
            System.exit();
        }
        // CONFIRM_NO: system already dismissed the overlay; nothing to do.
        return true;
    }

}
