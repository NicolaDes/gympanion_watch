import Toybox.Lang;
import Toybox.Application;
import Toybox.System;

// Manages all Application.Storage reads and writes for session state and events.
class PersistenceService {

    private const SESSION_KEY = "active_session";
    private const EVENTS_KEY  = "event_log";

    function initialize() {
    }

    // Serializes SessionState to a Dictionary and writes it to storage.
    function saveSession(sessionState as SessionState) as Void {
        var dict = sessionState.toDict();
        Application.Storage.setValue(SESSION_KEY, dict);
        System.println("[Persist] Session saved");
    }

    // Loads a SessionState from storage. Returns null if no saved session exists
    // or if the stored data is invalid.
    function loadSession() as SessionState or Null {
        var raw = Application.Storage.getValue(SESSION_KEY);
        if (raw == null) {
            System.println("[Persist] No saved session found");
            return null;
        }
        if (!(raw instanceof Dictionary)) {
            System.println("[Persist] Corrupt session data, ignoring");
            return null;
        }
        var dict = raw as Dictionary;
        var state = SessionState.fromDict(dict);
        System.println("[Persist] Session loaded: " + state.sessionId);
        return state;
    }

    // Removes the saved session key from storage.
    function clearSession() as Void {
        Application.Storage.deleteValue(SESSION_KEY);
        System.println("[Persist] Session cleared");
    }

    // Appends new events to the stored event log (read-modify-write).
    function saveEvents(events as Array) as Void {
        var raw = Application.Storage.getValue(EVENTS_KEY);
        var existing = new [0];
        if (raw != null && raw instanceof Array) {
            existing = raw as Array;
        }
        for (var i = 0; i < events.size(); i++) {
            existing.add(events[i]);
        }
        Application.Storage.setValue(EVENTS_KEY, existing);
    }

    // Returns the stored event log, or null if none exists.
    function loadEvents() as Array or Null {
        var raw = Application.Storage.getValue(EVENTS_KEY);
        if (raw == null || !(raw instanceof Array)) {
            return null;
        }
        return raw as Array;
    }

    // Removes the event log from storage.
    function clearEvents() as Void {
        Application.Storage.deleteValue(EVENTS_KEY);
        System.println("[Persist] Events cleared");
    }

}
