import Toybox.Lang;
import Toybox.Time;
import Toybox.System;

// Write-only append log for structured workout events.
// Events are immediately flushed to PersistenceService on each record() call.
class EventRecorder {

    private var _persistenceService as PersistenceService;
    private var _sessionId          as String;

    function initialize(persistenceService as PersistenceService) {
        _persistenceService = persistenceService;
        _sessionId          = "";
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
        _persistenceService.saveEvents([event]);
        System.println("[Event] " + type);
    }

}
