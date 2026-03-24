import Toybox.Lang;
import Toybox.WatchUi;

// WorkoutReplaceConfirmDelegate: handles the user's response to an incoming
// workout replacement request from the companion phone app.
// Yes -> tells CommService to apply the pending workout and notify the phone.
// No  -> tells CommService to discard the pending workout and notify the phone.
class WorkoutReplaceConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _commService as CompanionCommService;

    function initialize(commService as CompanionCommService) {
        ConfirmationDelegate.initialize();
        _commService = commService;
    }

    function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) {
            _commService.acceptPendingWorkout();
        } else {
            _commService.discardPendingWorkout();
        }
        return true;
    }

}
