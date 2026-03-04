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
    }

    // onStop() is called when the app is exiting. Persist and clean up.
    function onStop(state as Dictionary?) as Void {
        _engine.pause();
        System.println("[App] onStop: session saved, timer stopped");
    }

    // Returns the initial View + Delegate pair for the app.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [
            new DashboardView(_engine),
            new DashboardDelegate(_engine, _commService)
        ];
    }

}

function getApp() as gympApp {
    return Application.getApp() as gympApp;
}
