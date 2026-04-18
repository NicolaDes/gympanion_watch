import Toybox.Timer;
import Toybox.System;
import Toybox.Lang;

// Periodically triggers a liveStatus transmission to keep the iOS app
// informed of watch connectivity. Runs at 30s during active work,
// 60s during pause. Stopped on finish/exit.
class HeartbeatService {

    private var _timer as Timer.Timer or Null;
    private var _transmitter as LiveStatusTransmitter;
    private var _engine as WorkoutEngine;
    private var _intervalMs as Number;
    private var _running as Boolean;

    // Intervals in milliseconds
    private const ACTIVE_INTERVAL_MS = 30000;
    private const PAUSED_INTERVAL_MS = 60000;

    function initialize(transmitter as LiveStatusTransmitter, engine as WorkoutEngine) {
        _transmitter = transmitter;
        _engine = engine;
        _timer = null;
        _intervalMs = ACTIVE_INTERVAL_MS;
        _running = false;
    }

    // Starts the heartbeat at the active (30s) interval.
    // Safe to call multiple times — restarts the timer.
    function start() as Void {
        _intervalMs = ACTIVE_INTERVAL_MS;
        _restart();
        _running = true;
        System.println("[Heartbeat] Started at " + _intervalMs + "ms");
    }

    // Switches to the paused (60s) interval.
    function switchToPausedInterval() as Void {
        if (!_running) { return; }
        _intervalMs = PAUSED_INTERVAL_MS;
        _restart();
        System.println("[Heartbeat] Switched to paused interval " + _intervalMs + "ms");
    }

    // Switches back to the active (30s) interval.
    function switchToActiveInterval() as Void {
        if (!_running) { return; }
        _intervalMs = ACTIVE_INTERVAL_MS;
        _restart();
        System.println("[Heartbeat] Switched to active interval " + _intervalMs + "ms");
    }

    // Stops the heartbeat entirely.
    function stop() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        _running = false;
        System.println("[Heartbeat] Stopped");
    }

    // Returns whether the heartbeat is currently running.
    function isRunning() as Boolean {
        return _running;
    }

    // Timer callback — transmits the current state as a liveStatus.
    function onTick() as Void {
        var state = _engine.getCurrentState();
        var workout = _engine.getWorkout();
        if (state == null || workout == null) {
            stop();
            return;
        }

        // Don't heartbeat if finished or exited — should have been stopped already
        if (state.phase == PHASE_FINISHED || state.phase == PHASE_EXITED) {
            stop();
            return;
        }

        _transmitter.send(state, workout);
    }

    // Restarts the timer with the current interval. Uses repeating mode.
    private function _restart() as Void {
        if (_timer != null) {
            _timer.stop();
        }
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), _intervalMs, true);
    }

}
