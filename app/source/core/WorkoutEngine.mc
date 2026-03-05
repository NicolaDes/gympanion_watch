import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Attention;
import Toybox.System;

// WorkoutEngine is the central coordinator of all workout logic.
// It holds references to all services and manages phase transitions.
class WorkoutEngine {

    private var _workout         as Workout or Null;
    private var _sessionState    as SessionState or Null;
    private var _strategy        as TimelineStrategy;
    private var _timerService    as TimerService;
    private var _samplingEngine  as SamplingEngine;
    private var _eventRecorder   as EventRecorder;
    private var _persistenceService as PersistenceService;
    private var _workoutStarted  as Boolean;
    private var _onFinished      as Method or Null;

    function initialize(
        timerService     as TimerService,
        samplingEngine   as SamplingEngine,
        eventRecorder    as EventRecorder,
        persistenceService as PersistenceService
    ) {
        _timerService       = timerService;
        _samplingEngine     = samplingEngine;
        _eventRecorder      = eventRecorder;
        _persistenceService = persistenceService;
        _strategy           = new SequentialStrategy();
        _workout            = null;
        _sessionState       = null;
        _workoutStarted     = false;
        _onFinished         = null;
    }

    // Called once at boot with the loaded workout plan.
    function setWorkout(workout as Workout) as Void {
        _workout = workout;
    }

    // Registers a callback to invoke when the workout transitions to PHASE_FINISHED.
    // Used by DashboardDelegate to trigger the 3-second auto-return to summary.
    function setOnFinished(callback as Method) as Void {
        _onFinished = callback;
    }

    // Resets the session to start from the given exercise index.
    // Called when the user selects an exercise (or "Start") from the summary menu.
    function startFromExercise(exerciseIndex as Number) as Void {
        if (_workout == null) { return; }
        _timerService.stop();
        _persistenceService.clearSession();
        var sessionId = "session_" + Time.now().value().toString();
        _sessionState = new SessionState(sessionId, _workout.id);
        _sessionState.currentExerciseIndex = exerciseIndex;
        _workoutStarted = false;
        System.println("[Engine] startFromExercise(" + exerciseIndex + ")");
        WatchUi.requestUpdate();
    }

    // Creates a fresh session for the given workout. Resets all state to IDLE.
    function startNewSession(workout as Workout) as Void {
        _workout = workout;
        var sessionId = "session_" + Time.now().value().toString();
        _sessionState = new SessionState(sessionId, workout.id);
        _workoutStarted = false;
        System.println("[Engine] New session: " + sessionId);
    }

    // Restores engine state from a previously persisted SessionState.
    // Always resets to IDLE on restore (timer/phase context is lost on crash).
    function restoreSession(savedState as SessionState) as Void {
        _sessionState = savedState;
        // Normalize phase on restore: work/rest -> idle (user must press START again)
        var phase = _sessionState.phase;
        if (phase == PHASE_WORK || phase == PHASE_REST) {
            _sessionState.phase = PHASE_IDLE;
        }
        _workoutStarted = (_sessionState.completedSets.size() > 0);
        System.println("[Engine] Session restored, phase -> IDLE");
    }

    // Transitions from IDLE or REST to WORK phase. Starts the work timer.
    function startSet() as Void {
        if (_sessionState == null || _workout == null) { return; }
        var state = _sessionState;

        // Emit WorkoutStarted on very first user action
        if (!_workoutStarted) {
            _workoutStarted = true;
            var exercises = _workout.exercises;
            _eventRecorder.setSessionId(state.sessionId);
            _eventRecorder.record("WorkoutStarted", {
                "workoutId"     => _workout.id,
                "workoutName"   => _workout.name,
                "exerciseCount" => exercises.size()
            });
        }

        // Emit ExerciseStarted if this is the first set of this exercise
        if (state.currentSetIndex == 0) {
            var exercises = _workout.exercises;
            if (exercises != null && exercises.size() > state.currentExerciseIndex) {
                var ex = exercises[state.currentExerciseIndex] as Exercise;
                _eventRecorder.record("ExerciseStarted", {
                    "exerciseIndex" => state.currentExerciseIndex,
                    "exerciseName"  => ex.name,
                    "targetSets"    => ex.targetSets,
                    "targetReps"    => ex.targetReps,
                    "targetWeight"  => ex.targetWeight
                });
            }
        }

        state.phase        = PHASE_WORK;
        state.timerValueMs = 0;
        _samplingEngine.beginSet();
        _timerService.start(method(:onTimerTick), 1000);
        _persistenceService.saveSession(state);
        WatchUi.requestUpdate();
        System.println("[Engine] startSet -> PHASE_WORK");
    }

    // Called when a set is complete. Records the set, advances the timeline,
    // starts rest or finishes the workout.
    function completeSet(weight as Float, reps as Number) as Void {
        if (_sessionState == null || _workout == null) { return; }
        var state = _sessionState;

        // Finalize sampling
        var avgHr = _samplingEngine.finalizeSet();
        var nowTs = Time.now().value();

        // Record completed set in sessionState
        var setRecord = {
            "ei" => state.currentExerciseIndex,
            "si" => state.currentSetIndex,
            "w"  => weight,
            "r"  => reps,
            "hr" => avgHr != null ? avgHr : -1,
            "ts" => nowTs
        };
        state.completedSets.add(setRecord);

        // Emit SetCompleted event
        _eventRecorder.record("SetCompleted", {
            "exerciseIndex" => state.currentExerciseIndex,
            "setIndex"      => state.currentSetIndex,
            "weight"        => weight,
            "reps"          => reps,
            "avgHeartRate"  => avgHr != null ? avgHr : -1,
            "durationMs"    => state.timerValueMs
        });

        // Update last-used values (retained for session persistence)
        state.lastWeight = weight;
        state.lastReps   = reps;

        // Determine next state via strategy
        var result = _strategy.nextAction(state, _workout);
        var finished = result["finished"];

        if (finished) {
            // Workout complete
            _timerService.stop();
            state.phase = PHASE_FINISHED;
            _eventRecorder.record("WorkoutFinished", {
                "totalSets"       => state.completedSets.size(),
                "totalDurationMs" => nowTs - state.startTimestamp
            });
            _persistenceService.saveSession(state);
            System.println("[Engine] Workout FINISHED");
            if (_onFinished != null) {
                _onFinished.invoke();
            }
        } else {
            // Start rest
            var nextExerciseIndex = result["exerciseIndex"];
            var nextSetIndex      = result["setIndex"];
            state.currentExerciseIndex = nextExerciseIndex;
            state.currentSetIndex      = nextSetIndex;

            var exercises = _workout.exercises;
            // Determine which exercise's rest duration to use (the one just completed)
            // Find the exercise we just did (before the index advanced)
            var completedExerciseIndex = setRecord["ei"];
            var restDurationSec = 90; // fallback default
            if (exercises != null && completedExerciseIndex < exercises.size()) {
                var completedExercise = exercises[completedExerciseIndex] as Exercise;
                restDurationSec = completedExercise.restDurationSec;
            }

            state.phase         = PHASE_REST;
            state.restDurationMs = restDurationSec * 1000;
            state.timerValueMs  = state.restDurationMs;
            state.restAlertFired = false;

            _timerService.start(method(:onTimerTick), 1000);

            _eventRecorder.record("RestStarted", {
                "exerciseIndex"  => completedExerciseIndex,
                "restDurationMs" => state.restDurationMs
            });

            _persistenceService.saveSession(state);
            System.println("[Engine] completeSet -> PHASE_REST, restMs=" + state.restDurationMs);
        }

        WatchUi.requestUpdate();
    }

    // Cancels the current set and returns to WORK phase (restarts the work timer).
    function cancelSet() as Void {
        if (_sessionState == null) { return; }
        var state = _sessionState;
        state.phase        = PHASE_WORK;
        state.timerValueMs = 0;
        _samplingEngine.beginSet();
        _timerService.start(method(:onTimerTick), 1000);
        System.println("[Engine] cancelSet -> PHASE_WORK");
        WatchUi.requestUpdate();
    }

    // Returns a snapshot of current state for the UI to render.
    // Returns null if the engine is not yet initialized.
    function getCurrentState() as SessionState or Null {
        return _sessionState;
    }

    // Returns the current workout, or null if not loaded.
    function getWorkout() as Workout or Null {
        return _workout;
    }

    // Called every 1000ms by TimerService. Updates timer and triggers redraw.
    function onTimerTick() as Void {
        if (_sessionState == null) { return; }
        var state = _sessionState;

        if (state.phase == PHASE_WORK) {
            state.timerValueMs = state.timerValueMs + 1000;
            _samplingEngine.sample();
        } else if (state.phase == PHASE_REST) {
            state.timerValueMs = state.timerValueMs - 1000;

            // Fire haptic alert when rest reaches zero (only once)
            if (state.timerValueMs <= 0 && !state.restAlertFired) {
                state.restAlertFired = true;
                _fireRestAlert();
            }
        }

        WatchUi.requestUpdate();
    }

    // Clears the saved session and starts a brand-new one for the current workout.
    // Called when the user explicitly requests a fresh run (BACK on dashboard).
    function resetSession() as Void {
        _timerService.stop();
        _persistenceService.clearSession();
        if (_workout != null) {
            startNewSession(_workout);
        }
        System.println("[Engine] Session reset -> new session");
        WatchUi.requestUpdate();
    }

    // Stops the timer and persists current state. Called on app exit.
    function pause() as Void {
        _timerService.stop();
        if (_sessionState != null) {
            _persistenceService.saveSession(_sessionState);
        }
        System.println("[Engine] paused");
    }

    // Private: fires haptic vibration when rest countdown expires.
    private function _fireRestAlert() as Void {
        if (Attention has :vibrate) {
            var vibeData = [
                new Attention.VibeProfile(50, 250),
                new Attention.VibeProfile(0,  250),
                new Attention.VibeProfile(50, 250)
            ];
            Attention.vibrate(vibeData);
        }
        System.println("[Engine] REST ALERT - rest expired");
    }

}
