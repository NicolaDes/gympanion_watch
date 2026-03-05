import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// gympApp: Application entry point and service wiring harness.
// Creates all services and the WorkoutEngine during initialization,
// then wires them together. Acts as the application-lifetime DI container.
class gympApp extends Application.AppBase {

    private var _persistenceService as PersistenceService;
    private var _eventRecorder      as EventRecorder;
    private var _provider           as PhysiologicalProvider;
    private var _samplingEngine     as SamplingEngine;
    private var _timerService       as TimerService;
    private var _engine             as WorkoutEngine;
    private var _commService        as CompanionCommService;

    function initialize() {
        AppBase.initialize();

        // Create services in dependency order
        _persistenceService = new PersistenceService();
        _eventRecorder      = new EventRecorder(_persistenceService);
        _provider           = new MockPhysiologicalProvider();
        _samplingEngine     = new SamplingEngine(_provider, _eventRecorder);
        _timerService       = new TimerService();
        _engine             = new WorkoutEngine(
            _timerService,
            _samplingEngine,
            _eventRecorder,
            _persistenceService
        );
        _commService        = new CompanionCommService(_engine, _persistenceService);

        System.println("[App] Services initialized");
    }

    // onStart() is called after initialize(), once the app is running.
    // Prefers a previously received companion workout over the static default.
    // Attempts to restore a previously persisted session; otherwise starts fresh.
    function onStart(state as Dictionary?) as Void {
        // Determine which workout to use: companion workout takes priority over default.
        var companionDict = _persistenceService.loadCompanionWorkout();
        var workout;
        if (companionDict != null) {
            workout = _commService.deserializeWorkout(companionDict);
            if (workout == null) {
                // Stored data is corrupt; fall back to default and clear the bad entry.
                _persistenceService.clearCompanionWorkout();
                workout = StaticWorkoutLoader.loadDefaultWorkout();
                System.println("[App] Companion workout corrupt, using default");
            } else {
                System.println("[App] Using companion workout: " + workout.name);
            }
        } else {
            workout = StaticWorkoutLoader.loadDefaultWorkout();
            System.println("[App] No companion workout, using default");
        }
        _engine.setWorkout(workout);

        var savedState = _persistenceService.loadSession();
        if (savedState != null) {
            _engine.restoreSession(savedState);
            System.println("[App] Restored previous session");
        } else {
            _engine.startNewSession(workout);
            System.println("[App] Started new session");
        }

        // Register companion message listener (called in onStart, not initialize,
        // because the Communications module may not be ready during AppBase.initialize).
        _commService.startListening();

        // Register the summary rebuild callback so CommService can trigger it after accept
        _commService.setOnWorkoutAccepted(method(:onWorkoutAccepted));
    }

    // onStop() is called when the app is exiting. Persist and clean up.
    function onStop(state as Dictionary?) as Void {
        _engine.pause();
        System.println("[App] onStop: session saved, timer stopped");
    }

    // Called by CompanionCommService after a pending workout is accepted.
    // Rebuilds the summary menu with the new workout and switches to it,
    // replacing the stale menu that was built at app start.
    function onWorkoutAccepted() as Void {
        var workout = _engine.getWorkout();
        var title = (workout != null) ? workout.name : "GymPanion";
        var menu = new WatchUi.Menu2({:title => title});

        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.LabelStart) as String,
            null, -1, {}
        ));

        if (workout != null && workout.exercises != null) {
            var exercises = workout.exercises;
            for (var i = 0; i < exercises.size(); i++) {
                var ex = exercises[i] as Exercise;
                menu.addItem(new WatchUi.MenuItem(ex.name, null, i, {}));
            }
        }

        WatchUi.switchToView(menu, new WorkoutSummaryDelegate(_engine, _commService), WatchUi.SLIDE_IMMEDIATE);
        System.println("[App] Summary menu rebuilt for new workout");
    }

    // Returns the summary menu as the initial view.
    // Lists "Start" plus each exercise by name; selecting any item
    // starts the workout from that exercise and pushes the dashboard.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var workout = _engine.getWorkout();

        var title = (workout != null) ? workout.name : "GymPanion";
        var menu = new WatchUi.Menu2({:title => title});

        // "Start" item — always starts from exercise 0
        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.LabelStart) as String,
            null, -1, {}
        ));

        // One item per exercise, in order
        if (workout != null && workout.exercises != null) {
            var exercises = workout.exercises;
            for (var i = 0; i < exercises.size(); i++) {
                var ex = exercises[i] as Exercise;
                menu.addItem(new WatchUi.MenuItem(ex.name, null, i, {}));
            }
        }

        return [menu, new WorkoutSummaryDelegate(_engine, _commService)];
    }

}

function getApp() as gympApp {
    return Application.getApp() as gympApp;
}
