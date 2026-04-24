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
    private var _transmitter        as LiveStatusTransmitter;
    private var _outboundBuffer     as OutboundBufferService;
    private var _commService        as CompanionCommService;

    function initialize() {
        AppBase.initialize();

        // Create services in dependency order
        _persistenceService = new PersistenceService();
        _eventRecorder      = new EventRecorder(_persistenceService);
        _provider           = new RealPhysiologicalProvider();
        _samplingEngine     = new SamplingEngine(_provider, _eventRecorder);
        _timerService       = new TimerService();
        _transmitter        = new LiveStatusTransmitter(_provider);
        _engine             = new WorkoutEngine(
            _timerService,
            _samplingEngine,
            _eventRecorder,
            _persistenceService,
            _transmitter
        );

        _outboundBuffer = new OutboundBufferService(_persistenceService);
        _commService    = new CompanionCommService(_engine, _persistenceService, _outboundBuffer);
        _outboundBuffer.setCommService(_commService);

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

        // Kick a flush in case the app was resumed with pending data.
        _outboundBuffer.pruneOrphanGiveUpEntries();
        _outboundBuffer.flushIfPossible();
    }

    // onStop() is called when the app is exiting. Persist and clean up.
    function onStop(state as Dictionary?) as Void {
        // Best-effort: send EXITED phase to iOS before shutdown
        var sessionState = _engine.getCurrentState();
        var workout = _engine.getWorkout();
        if (sessionState != null && workout != null
            && sessionState.phase != PHASE_FINISHED
            && sessionState.phase != PHASE_IDLE) {
            sessionState.phase = PHASE_EXITED;
            _transmitter.send(sessionState, workout);
        }

        _engine.pause();
        System.println("[App] onStop: EXITED sent, session saved");
    }

    // Called by CompanionCommService after a pending workout is accepted.
    // Rebuilds the summary menu with the new workout and switches to it,
    // replacing the stale menu that was built at app start.
    function onWorkoutAccepted() as Void {
        var workout = _engine.getWorkout();
        var menu = _buildSummaryMenu(workout);
        WatchUi.switchToView(menu, new WorkoutSummaryDelegate(_engine, _commService, _outboundBuffer), WatchUi.SLIDE_IMMEDIATE);
        System.println("[App] Summary menu rebuilt for new workout");
    }

    // Returns the summary menu as the initial view.
    // Lists "Start" plus one entry per block; selecting any item
    // starts the workout from that block and pushes the dashboard.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var workout = _engine.getWorkout();
        var menu = _buildSummaryMenu(workout);
        return [menu, new WorkoutSummaryDelegate(_engine, _commService, _outboundBuffer)];
    }

    // Builds a Menu2 with "Start" plus one entry per block.
    private function _buildSummaryMenu(workout as Workout or Null) as WatchUi.Menu2 {
        var title = (workout != null) ? workout.name : "GymPanion";
        var menu = new WatchUi.Menu2({:title => title});

        menu.addItem(new WatchUi.MenuItem(
            WatchUi.loadResource(Rez.Strings.LabelStart) as String,
            null, -1, {}
        ));

        if (workout != null && workout.blocks != null) {
            var blocks = workout.blocks;
            for (var i = 0; i < blocks.size(); i++) {
                var block = blocks[i] as WorkoutBlock;
                var blockLabel = block.name;
                if (blockLabel.length() == 0) {
                    // Fallback label based on type
                    if (block.type == BLOCK_EMOM) { blockLabel = "EMOM"; }
                    else if (block.type == BLOCK_AMRAP) { blockLabel = "AMRAP"; }
                    else { blockLabel = "Block " + (i + 1).toString(); }
                }
                menu.addItem(new WatchUi.MenuItem(blockLabel, null, i, {}));
            }
        }

        return menu;
    }

}

function getApp() as gympApp {
    return Application.getApp() as gympApp;
}
