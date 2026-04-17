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
    private var _resultSerializer as SessionResultSerializer;
    private var _workoutStarted  as Boolean;
    private var _onFinished      as Method or Null;
    private var _transmitter     as LiveStatusTransmitter;

    function initialize(
        timerService     as TimerService,
        samplingEngine   as SamplingEngine,
        eventRecorder    as EventRecorder,
        persistenceService as PersistenceService,
        transmitter      as LiveStatusTransmitter
    ) {
        _timerService       = timerService;
        _samplingEngine     = samplingEngine;
        _eventRecorder      = eventRecorder;
        _persistenceService = persistenceService;
        _transmitter        = transmitter;
        _strategy           = new SequentialStrategy();
        _resultSerializer   = new SessionResultSerializer();
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

    // Starts a fresh session from the given block index.
    // (Renamed from startFromExercise — now block-aware.)
    function startFromBlock(blockIndex as Number) as Void {
        if (_workout == null) { return; }
        _timerService.stop();
        _persistenceService.clearSession();
        var sessionId = "session_" + Time.now().value().toString();
        _sessionState = new SessionState(sessionId, _workout.id);
        _sessionState.currentBlockIndex = blockIndex;
        _sessionState.currentExerciseIndex = 0;
        _sessionState.currentSetIndex = 0;
        _workoutStarted = false;
        _switchStrategyForCurrentBlock();
        System.println("[Engine] startFromBlock(" + blockIndex + ")");
        WatchUi.requestUpdate();
    }

    // Creates a fresh session for the given workout. Resets all state to IDLE.
    function startNewSession(workout as Workout) as Void {
        _workout = workout;
        var sessionId = "session_" + Time.now().value().toString();
        _sessionState = new SessionState(sessionId, workout.id);
        _workoutStarted = false;
        _switchStrategyForCurrentBlock();
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
        // Also normalize BLOCK_COMPLETE to IDLE on restore
        if (_sessionState.phase == PHASE_BLOCK_COMPLETE) {
            _sessionState.phase = PHASE_IDLE;
        }
        _workoutStarted = (_sessionState.completedSets.size() > 0);
        _switchStrategyForCurrentBlock();
        System.println("[Engine] Session restored, phase -> IDLE");
    }

    // Returns the current block, or null
    function getCurrentBlock() as WorkoutBlock or Null {
        if (_workout == null || _sessionState == null) { return null; }
        var blocks = _workout.blocks;
        if (blocks == null || _sessionState.currentBlockIndex >= blocks.size()) { return null; }
        return blocks[_sessionState.currentBlockIndex] as WorkoutBlock;
    }

    // Returns the current BlockSet for sequential blocks, or null
    function getCurrentBlockSet() as BlockSet or Null {
        var block = getCurrentBlock();
        if (block == null || block.type != BLOCK_SEQUENTIAL) { return null; }
        var exercises = block.exercises;
        if (exercises == null || _sessionState == null) { return null; }
        var exIdx = _sessionState.currentExerciseIndex;
        if (exIdx >= exercises.size()) { return null; }
        var ex = exercises[exIdx] as Exercise;
        if (ex.sets == null) { return null; }
        var setIdx = _sessionState.currentSetIndex;
        if (setIdx >= ex.sets.size()) { return null; }
        return ex.sets[setIdx] as BlockSet;
    }

    // Returns the current BlockSet for EMOM/AMRAP blocks via the active strategy.
    // Falls back to the sequential getCurrentBlockSet() for sequential blocks.
    function getActiveBlockSet() as BlockSet or Null {
        if (_workout == null || _sessionState == null) { return null; }
        var block = getCurrentBlock();
        if (block == null) { return null; }

        if (block.type == BLOCK_EMOM && _strategy instanceof EmomStrategy) {
            return (_strategy as EmomStrategy).getCurrentBlockSet(_sessionState, _workout);
        }
        if (block.type == BLOCK_AMRAP && _strategy instanceof AmrapStrategy) {
            return (_strategy as AmrapStrategy).getCurrentBlockSet(_sessionState, _workout);
        }
        // Sequential: use existing method
        return getCurrentBlockSet();
    }

    // Returns the display name of the current exercise, resolved from the active block.
    function getCurrentExerciseName() as String {
        var bs = getActiveBlockSet();
        if (bs != null) { return bs.name; }

        // Sequential fallback: use flat exercises array
        if (_workout != null && _sessionState != null) {
            var block = getCurrentBlock();
            if (block != null && block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
                var exIdx = _sessionState.currentExerciseIndex;
                if (exIdx < block.exercises.size()) {
                    var ex = block.exercises[exIdx] as Exercise;
                    return ex.name;
                }
            }
        }
        return "---";
    }

    // Returns the target reps for the current exercise/set.
    function getCurrentTargetReps() as Number {
        var bs = getActiveBlockSet();
        if (bs != null && bs.reps != null) { return bs.reps; }

        // Sequential fallback
        if (_workout != null && _sessionState != null) {
            var block = getCurrentBlock();
            if (block != null && block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
                var exIdx = _sessionState.currentExerciseIndex;
                if (exIdx < block.exercises.size()) {
                    var ex = block.exercises[exIdx] as Exercise;
                    return ex.targetReps;
                }
            }
        }
        return 0;
    }

    // Returns the target weight for the current exercise/set.
    function getCurrentTargetWeight() as Float {
        var bs = getActiveBlockSet();
        if (bs != null && bs.wKg != null) { return bs.wKg; }

        // Sequential fallback
        if (_workout != null && _sessionState != null) {
            var block = getCurrentBlock();
            if (block != null && block.type == BLOCK_SEQUENTIAL && block.exercises != null) {
                var exIdx = _sessionState.currentExerciseIndex;
                if (exIdx < block.exercises.size()) {
                    var ex = block.exercises[exIdx] as Exercise;
                    return ex.targetWeight;
                }
            }
        }
        return 0.0f;
    }

    // Returns total sets for the current sequential exercise, or 0 for EMOM/AMRAP.
    function getCurrentTotalSets() as Number {
        var block = getCurrentBlock();
        if (block == null || _sessionState == null) { return 0; }
        if (block.type != BLOCK_SEQUENTIAL || block.exercises == null) { return 0; }

        var exIdx = _sessionState.currentExerciseIndex;
        if (exIdx >= block.exercises.size()) { return 0; }
        var ex = block.exercises[exIdx] as Exercise;
        if (ex.sets != null) { return ex.sets.size(); }
        return ex.targetSets;
    }

    // Switches the active strategy based on the current block type.
    // Called when starting a new block or restoring a session.
    private function _switchStrategyForCurrentBlock() as Void {
        var block = getCurrentBlock();
        if (block == null) {
            _strategy = new SequentialStrategy();
            return;
        }
        if (block.type == BLOCK_EMOM) {
            _strategy = new EmomStrategy();
        } else if (block.type == BLOCK_AMRAP) {
            _strategy = new AmrapStrategy();
        } else {
            _strategy = new SequentialStrategy();
        }
        System.println("[Engine] Strategy switched to " + block.type.toString());
    }

    // Advances to the next block. Sets phase to BLOCK_COMPLETE if more blocks
    // remain, or FINISHED if this was the last block.
    private function _advanceBlock() as Void {
        if (_sessionState == null || _workout == null) { return; }
        var state = _sessionState;

        state.currentBlockIndex = state.currentBlockIndex + 1;
        state.currentExerciseIndex = 0;
        state.currentSetIndex = 0;
        state.currentRoundIndex = 0;

        if (_workout.blocks != null && state.currentBlockIndex < _workout.blocks.size()) {
            state.phase = PHASE_BLOCK_COMPLETE;
            _switchStrategyForCurrentBlock();
            _transmitter.send(state, _workout);
            System.println("[Engine] Block complete, next block: " + state.currentBlockIndex);
        } else {
            _timerService.stop();
            state.phase = PHASE_FINISHED;
            _transmitter.send(state, _workout);
            var nowTs = Time.now().value();
            _eventRecorder.record("WorkoutFinished", {
                "totalSets"       => state.completedSets.size(),
                "totalDurationMs" => nowTs - state.startTimestamp
            });
            _persistenceService.clearEvents();
            System.println("[Engine] All blocks complete -> FINISHED");
            if (_onFinished != null) {
                _onFinished.invoke();
            }
        }
        _persistenceService.saveSession(state);
        WatchUi.requestUpdate();
    }

    // Transitions from IDLE, REST, or BLOCK_COMPLETE to WORK phase.
    // Block-aware: handles sequential, EMOM, and AMRAP start logic.
    function startSet() as Void {
        if (_sessionState == null || _workout == null) { return; }
        var state = _sessionState;
        var block = getCurrentBlock();
        if (block == null) { return; }

        // Emit WorkoutStarted on very first user action
        if (!_workoutStarted) {
            _workoutStarted = true;
            _eventRecorder.setSessionId(state.sessionId);
            _eventRecorder.record("WorkoutStarted", {
                "workoutId"   => _workout.id,
                "workoutName" => _workout.name
            });
            _transmitter.send(state, _workout);
        }

        var nowTs = Time.now().value();

        if (block.type == BLOCK_EMOM) {
            // EMOM: start the interval countdown
            state.phase = PHASE_WORK;
            state.roundStartTimestamp = nowTs;
            if (state.blockStartTimestamp == 0) {
                state.blockStartTimestamp = nowTs;
            }
            state.timerValueMs = (block.intervalSec != null ? block.intervalSec : 60) * 1000;
            _samplingEngine.beginSet();
            _timerService.start(method(:onTimerTick), 1000);
        } else if (block.type == BLOCK_AMRAP) {
            // AMRAP: start the total countdown
            state.phase = PHASE_WORK;
            state.blockStartTimestamp = nowTs;
            state.timerValueMs = (block.timeCapSec != null ? block.timeCapSec : 600) * 1000;
            _samplingEngine.beginSet();
            _timerService.start(method(:onTimerTick), 1000);
        } else {
            // Sequential: existing logic
            if (state.currentSetIndex == 0) {
                var exercises = block.exercises;
                if (exercises != null && state.currentExerciseIndex < exercises.size()) {
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
        }

        _persistenceService.saveSession(state);
        WatchUi.requestUpdate();
        System.println("[Engine] startSet -> PHASE_WORK (block type=" + block.type + ")");
    }

    // Called when a set is complete. Routes to block-type-specific completion logic.
    function completeSet(weight as Float, reps as Number) as Void {
        if (_sessionState == null || _workout == null) { return; }
        var block = getCurrentBlock();
        if (block == null) { return; }

        if (block.type == BLOCK_EMOM) {
            _completeEmomSet(weight, reps);
        } else if (block.type == BLOCK_AMRAP) {
            _completeAmrapSet(weight, reps);
        } else {
            _completeSequentialSet(weight, reps);
        }
    }

    // Sequential set completion: existing logic, now block-scoped.
    private function _completeSequentialSet(weight as Float, reps as Number) as Void {
        var state = _sessionState;
        var block = getCurrentBlock();

        var avgHr = _samplingEngine.finalizeSet();
        var peakHr = _samplingEngine.getPeakHr();
        var nowTs = Time.now().value();

        var setRecord = {
            "ei"     => state.currentExerciseIndex,
            "si"     => state.currentSetIndex,
            "w"      => weight,
            "r"      => reps,
            "hr"     => avgHr != null ? avgHr : -1,
            "peakHr" => peakHr,
            "durMs"  => state.timerValueMs,
            "ts"     => nowTs
        };
        state.completedSets.add(setRecord);

        _eventRecorder.record("SetCompleted", {
            "exerciseIndex" => state.currentExerciseIndex,
            "setIndex"      => state.currentSetIndex,
            "weight"        => weight,
            "reps"          => reps,
            "avgHeartRate"  => avgHr != null ? avgHr : -1,
            "peakHeartRate" => peakHr,
            "durationMs"    => state.timerValueMs
        });

        state.lastWeight = weight;
        state.lastReps   = reps;

        var result = _strategy.nextAction(state, _workout);
        var finished = result["finished"];

        if (finished) {
            _timerService.stop();
            // Build sequential block result
            if (block != null && block.exercises != null) {
                var blockResult = _resultSerializer.serializeSequentialBlockResult(
                    state.currentBlockIndex,
                    block.exercises,
                    state.completedSets
                );
                state.blockResults.add(blockResult);
            }
            // Clear completed sets for this block (next block starts fresh)
            state.completedSets = new [0];
            _advanceBlock();
        } else {
            var nextExerciseIndex = result["exerciseIndex"];
            var nextSetIndex      = result["setIndex"];
            var prevExerciseIndex = state.currentExerciseIndex;
            state.currentExerciseIndex = nextExerciseIndex;
            state.currentSetIndex      = nextSetIndex;

            // Transmit live status on exercise transition
            if (nextExerciseIndex != prevExerciseIndex) {
                _transmitter.send(state, _workout);
            }

            // Determine rest duration from BlockSet or Exercise
            var blockSet = getCurrentBlockSet();
            var restDurationSec = 90;
            if (blockSet != null && blockSet.restSec != null) {
                restDurationSec = blockSet.restSec;
            } else if (block != null && block.exercises != null) {
                var completedExIdx = setRecord["ei"];
                if (completedExIdx < block.exercises.size()) {
                    var completedEx = block.exercises[completedExIdx] as Exercise;
                    restDurationSec = completedEx.restDurationSec;
                }
            }

            state.phase         = PHASE_REST;
            state.restDurationMs = restDurationSec * 1000;
            state.timerValueMs  = state.restDurationMs;
            state.restAlertFired = false;

            _timerService.start(method(:onTimerTick), 1000);
            _persistenceService.saveSession(state);
            System.println("[Engine] completeSequentialSet -> REST, restMs=" + state.restDurationMs);
        }

        WatchUi.requestUpdate();
    }

    // EMOM set completion: marks exercise done within current round.
    // The user pressed START to say "I finished this exercise."
    // If there are more exercises in the round, advance setIndex.
    // Otherwise, wait for interval to expire (handled by tick).
    private function _completeEmomSet(weight as Float, reps as Number) as Void {
        var state = _sessionState;
        var nowTs = Time.now().value();
        var avgHr = _samplingEngine.finalizeSet();
        var peakHr = _samplingEngine.getPeakHr();

        var setRecord = {
            "bi"     => state.currentBlockIndex,
            "ri"     => state.currentRoundIndex,
            "si"     => state.currentSetIndex,
            "w"      => weight,
            "r"      => reps,
            "hr"     => avgHr != null ? avgHr : -1,
            "peakHr" => peakHr,
            "durMs"  => (nowTs - state.roundStartTimestamp) * 1000,
            "ts"     => nowTs
        };
        state.completedSets.add(setRecord);

        var result = _strategy.nextAction(state, _workout);
        var roundFinished = result["roundFinished"];

        if (roundFinished != null && roundFinished == true) {
            // All exercises in this round done — wait for interval timer
            // Phase stays WORK but user sees remaining interval time
            state.phase = PHASE_REST; // visual: "rest" until interval expires
            _transmitter.send(state, _workout);
            System.println("[Engine] EMOM round " + state.currentRoundIndex + " exercises done, waiting for interval");
        } else {
            // More exercises in this round
            state.currentSetIndex = result["setIndex"];
            _samplingEngine.beginSet();
            System.println("[Engine] EMOM advanced to set " + state.currentSetIndex);
        }

        _persistenceService.saveSession(state);
        WatchUi.requestUpdate();
    }

    // AMRAP set completion: marks exercise done, cycles template.
    private function _completeAmrapSet(weight as Float, reps as Number) as Void {
        var state = _sessionState;
        var nowTs = Time.now().value();
        var avgHr = _samplingEngine.finalizeSet();
        var peakHr = _samplingEngine.getPeakHr();

        var setRecord = {
            "bi"     => state.currentBlockIndex,
            "ri"     => state.amrapRoundsCompleted,
            "si"     => state.currentSetIndex,
            "w"      => weight,
            "r"      => reps,
            "hr"     => avgHr != null ? avgHr : -1,
            "peakHr" => peakHr,
            "ts"     => nowTs
        };
        state.completedSets.add(setRecord);

        var result = _strategy.nextAction(state, _workout);
        var roundComplete = result["roundComplete"];

        if (roundComplete != null && roundComplete == true) {
            state.amrapRoundsCompleted = state.amrapRoundsCompleted + 1;
            state.currentSetIndex = 0;
            state.amrapPartialReps = 0;
            _transmitter.send(state, _workout);
            System.println("[Engine] AMRAP round " + state.amrapRoundsCompleted + " complete");
        } else {
            state.currentSetIndex = result["setIndex"];
            state.amrapPartialReps = state.amrapPartialReps + 1;
        }

        _samplingEngine.beginSet();
        _persistenceService.saveSession(state);
        WatchUi.requestUpdate();
    }

    // Builds the session result payload for transmission to the phone.
    function getSessionResultPayload() as Dictionary or Null {
        if (_sessionState == null || _workout == null) { return null; }
        return _resultSerializer.serialize(_sessionState, _workout);
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

    // Returns the active strategy. Used by DashboardView for block-specific queries.
    function getStrategy() as TimelineStrategy {
        return _strategy;
    }

    // Called every 1000ms by TimerService. Routes to block-type-specific tick logic.
    function onTimerTick() as Void {
        if (_sessionState == null || _workout == null) { return; }
        var state = _sessionState;
        var block = getCurrentBlock();

        if (block != null && block.type == BLOCK_EMOM) {
            _onEmomTick(state, block);
        } else if (block != null && block.type == BLOCK_AMRAP) {
            _onAmrapTick(state, block);
        } else {
            _onSequentialTick(state);
        }

        WatchUi.requestUpdate();
    }

    // Sequential tick: existing count-up (work) / count-down (rest) logic.
    private function _onSequentialTick(state as SessionState) as Void {
        if (state.phase == PHASE_WORK) {
            state.timerValueMs = state.timerValueMs + 1000;
            _samplingEngine.sample();
        } else if (state.phase == PHASE_REST) {
            state.timerValueMs = state.timerValueMs - 1000;
            if (state.timerValueMs <= 0 && !state.restAlertFired) {
                state.restAlertFired = true;
                _fireRestAlert();
            }
        }
    }

    // EMOM tick: interval countdown with auto-advance to next round.
    private function _onEmomTick(state as SessionState, block as WorkoutBlock) as Void {
        if (state.phase != PHASE_WORK && state.phase != PHASE_REST) { return; }

        _samplingEngine.sample();

        // Check total time first
        if (block.intervalSec != null && block.rounds != null) {
            var totalDurationSec = block.intervalSec * block.rounds.size();
            var totalElapsed = Time.now().value() - state.blockStartTimestamp;

            if (totalElapsed >= totalDurationSec) {
                // EMOM block time is up — finish block
                _timerService.stop();
                _fireRestAlert();

                // Build EMOM block result
                var roundResults = _buildEmomRoundResults(state, block);
                var blockResult = _resultSerializer.serializeEmomBlockResult(
                    state.currentBlockIndex,
                    block.intervalSec,
                    roundResults
                );
                state.blockResults.add(blockResult);
                state.completedSets = new [0];
                _advanceBlock();
                return;
            }
        }

        // Update interval countdown
        var intervalElapsed = Time.now().value() - state.roundStartTimestamp;
        var intervalSec = block.intervalSec != null ? block.intervalSec : 60;
        var remaining = intervalSec - intervalElapsed;
        state.timerValueMs = remaining * 1000;

        // Interval expired — advance to next round
        if (remaining <= 0) {
            _fireRestAlert();
            state.currentRoundIndex = state.currentRoundIndex + 1;
            state.currentSetIndex = 0;
            state.roundStartTimestamp = Time.now().value();
            state.timerValueMs = intervalSec * 1000;
            state.phase = PHASE_WORK;
            _samplingEngine.beginSet();
            System.println("[Engine] EMOM auto-advance to round " + state.currentRoundIndex);
        }
    }

    // AMRAP tick: total countdown, auto-finish when time is up.
    private function _onAmrapTick(state as SessionState, block as WorkoutBlock) as Void {
        if (state.phase != PHASE_WORK) { return; }

        _samplingEngine.sample();

        var timeCapSec = block.timeCapSec != null ? block.timeCapSec : 600;
        var elapsed = Time.now().value() - state.blockStartTimestamp;
        var remaining = timeCapSec - elapsed;
        state.timerValueMs = remaining * 1000;

        if (remaining <= 0) {
            // AMRAP time is up
            _timerService.stop();
            _fireRestAlert();
            state.timerValueMs = 0;

            // Build AMRAP block result
            var roundResults = _buildAmrapRoundResults(state, block);
            var blockResult = _resultSerializer.serializeAmrapBlockResult(
                state.currentBlockIndex,
                timeCapSec,
                state.amrapRoundsCompleted,
                state.amrapPartialReps,
                roundResults
            );
            state.blockResults.add(blockResult);
            state.completedSets = new [0];
            _advanceBlock();
        }
    }

    // Builds round result arrays for EMOM block result serialization.
    private function _buildEmomRoundResults(state as SessionState, block as WorkoutBlock) as Array {
        var results = new [0];
        if (block.rounds == null) { return results; }

        var rounds = block.rounds;
        for (var ri = 0; ri < rounds.size(); ri++) {
            var roundSets = new [0];
            for (var j = 0; j < state.completedSets.size(); j++) {
                var rec = state.completedSets[j] as Dictionary;
                if (rec["ri"] == ri) {
                    roundSets.add({
                        "exId"  => rec["si"],
                        "reps"  => rec["r"],
                        "wKg"   => rec["w"],
                        "avgHr" => rec["hr"]
                    });
                }
            }
            // Estimate time-to-complete from first set timestamp
            var intervalSec = block.intervalSec != null ? block.intervalSec : 60;
            results.add({
                "ri"   => ri,
                "ttc"  => roundSets.size() > 0 ? intervalSec : 0,
                "trem" => 0,
                "sets" => roundSets
            });
        }
        return results;
    }

    // Builds round result arrays for AMRAP block result serialization.
    private function _buildAmrapRoundResults(state as SessionState, block as WorkoutBlock) as Array {
        var results = new [0];
        var templateSize = (block.sets != null) ? block.sets.size() : 1;

        // Group completed sets by round
        var maxRound = state.amrapRoundsCompleted;
        if (state.amrapPartialReps > 0) { maxRound = maxRound + 1; }

        for (var ri = 0; ri <= maxRound && ri <= state.amrapRoundsCompleted; ri++) {
            var roundSets = new [0];
            for (var j = 0; j < state.completedSets.size(); j++) {
                var rec = state.completedSets[j] as Dictionary;
                if (rec["ri"] == ri) {
                    roundSets.add({
                        "exId"  => rec["si"],
                        "reps"  => rec["r"],
                        "wKg"   => rec["w"],
                        "avgHr" => rec["hr"]
                    });
                }
            }
            var isPartial = (ri == state.amrapRoundsCompleted && state.amrapPartialReps > 0);
            results.add({
                "ri"      => ri,
                "durMs"   => 0,
                "partial" => isPartial,
                "sets"    => roundSets
            });
        }
        return results;
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
