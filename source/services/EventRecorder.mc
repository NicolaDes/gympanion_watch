import Toybox.Lang;
import Toybox.Time;
import Toybox.System;

// Write-only append log for structured workout events.
// Events are buffered and flushed to PersistenceService on each record() call.
class EventRecorder {

    private var _persistenceService as PersistenceService;
    private var _sessionId          as String;
    private var _buffer             as Array;

    function initialize(persistenceService as PersistenceService) {
        _persistenceService = persistenceService;
        _sessionId          = "";
        _buffer             = new [0];
    }

    // Sets the session ID used to tag all subsequent events.
    function setSessionId(sessionId as String) as Void {
        _sessionId = sessionId;
    }

    // Records an event with the given type and payload Dictionary.
    // Immediately flushes to persistent storage.
    function record(type as String, payload as Dictionary) as Void {
        var event = {
            "t"   => type,
            "ts"  => Time.now().value(),
            "sid" => _sessionId,
            "p"   => payload
        };
        _buffer.add(event);
        _persistenceService.saveEvents([event]);
        System.println("[Event] " + type);
    }

}
