import Toybox.Lang;
import Toybox.Timer;

// Wraps Toybox.Timer.Timer to ensure only one Timer object is ever allocated.
// Garmin devices have a hard limit on concurrent timers.
class TimerService {

    private var _timer as Timer.Timer;
    private var _running as Boolean;

    function initialize() {
        _timer   = new Timer.Timer();
        _running = false;
    }

    // Starts (or restarts) the repeating timer with the given callback and interval.
    function start(callback as Method, intervalMs as Number) as Void {
        if (_running) {
            _timer.stop();
        }
        _timer.start(callback, intervalMs, true);
        _running = true;
    }

    // Stops the timer. Safe to call even if the timer is not running.
    function stop() as Void {
        if (_running) {
            _timer.stop();
            _running = false;
        }
    }

    function isRunning() as Boolean {
        return _running;
    }

}
