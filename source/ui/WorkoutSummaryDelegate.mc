import Toybox.Lang;
import Toybox.WatchUi;

// WorkoutSummaryDelegate: handles input on the workout summary menu.
// Selecting any item starts the workout from the corresponding exercise.
// Back shows the exit confirmation dialog.
class WorkoutSummaryDelegate extends WatchUi.Menu2InputDelegate {

    private var _engine      as WorkoutEngine;
    private var _commService as CompanionCommService;

    function initialize(engine as WorkoutEngine, commService as CompanionCommService) {
        Menu2InputDelegate.initialize();
        _engine      = engine;
        _commService = commService;
    }

    // Called when the user selects a menu item.
    // Item id -1 means "Start" (exercise 0); id >= 0 means that exercise index.
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var startIndex = 0;
        if (id instanceof Number && (id as Number) >= 0) {
            startIndex = id as Number;
        }
        _engine.startFromExercise(startIndex);
        WatchUi.pushView(
            new DashboardView(_engine),
            new DashboardDelegate(_engine, _commService),
            WatchUi.SLIDE_UP
        );
    }

    // Back on the summary shows the exit confirmation dialog.
    function onBack() as Void {
        var dialog = new WatchUi.Confirmation(
            WatchUi.loadResource(Rez.Strings.exitConfirmMsg) as String
        );
        WatchUi.pushView(dialog, new ExitConfirmDelegate(_engine), WatchUi.SLIDE_IMMEDIATE);
    }

}
