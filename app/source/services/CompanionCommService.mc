import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// CompanionCommService: Manages phone-to-watch communication via the
// Toybox.Communications API. Receives workout payloads from the companion
// app, deserializes them into domain objects, persists them, and notifies
// the WorkoutEngine to restart with the new workout.
//
// Call startListening() once during app startup (in onStart).
// The system invokes onMessageReceived() whenever the companion app sends
// a message to this watch app.
class CompanionCommService {

    private var _engine as WorkoutEngine;
    private var _persistenceService as PersistenceService;

    function initialize(engine as WorkoutEngine, persistenceService as PersistenceService) {
        _engine = engine;
        _persistenceService = persistenceService;
    }

    // Registers the phone message listener with the Communications API.
    // Must be called exactly once per app lifecycle, in onStart().
    // Guard with `has` check to handle devices / API levels where the
    // method is unavailable.
    function startListening() as Void {
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onMessageReceived));
            System.println("[Comm] Listening for phone messages");
        } else {
            System.println("[Comm] registerForPhoneAppMessages not available on this device");
        }
    }

    // Callback invoked by the system when a message arrives from the companion app.
    // msg.data contains the payload sent by the companion (a Dictionary when well-formed).
    // This method is non-private so the Communications runtime can invoke it via method(:...).
    function onMessageReceived(msg as Communications.PhoneAppMessage) as Void {
        System.println("[Comm] Message received from companion");
        var data = msg.data;
        if (data == null || !(data instanceof Dictionary)) {
            System.println("[Comm] Invalid payload: not a Dictionary");
            return;
        }
        var dict = data as Dictionary;
        var workout = deserializeWorkout(dict);
        if (workout == null) {
            System.println("[Comm] Failed to deserialize workout");
            return;
        }

        // Persist the raw dictionary so it survives app restarts
        _persistenceService.saveCompanionWorkout(dict);

        // Clear any in-progress session and start fresh with the new workout
        _persistenceService.clearSession();
        _engine.setWorkout(workout);
        _engine.startNewSession(workout);

        System.println("[Comm] Workout loaded: " + workout.name);
        WatchUi.requestUpdate();
    }

    // Deserializes a raw Dictionary payload (from Communications or Storage)
    // into a Workout domain object. Returns null if required fields are
    // missing or the payload is otherwise invalid.
    //
    // Public so gympApp.onStart() can re-deserialize stored companion workout
    // Dictionaries without duplicating this logic.
    function deserializeWorkout(dict as Dictionary) as Workout or Null {
        var id           = dict["id"];
        var name         = dict["name"];
        var exercisesRaw = dict["exercises"];

        if (id == null || name == null || exercisesRaw == null) {
            System.println("[Comm] Workout missing required top-level fields");
            return null;
        }
        if (!(exercisesRaw instanceof Array)) {
            System.println("[Comm] 'exercises' field is not an Array");
            return null;
        }

        var rawArray  = exercisesRaw as Array;
        var exercises = new [0];

        for (var i = 0; i < rawArray.size(); i++) {
            var exDict = rawArray[i];
            if (exDict == null || !(exDict instanceof Dictionary)) {
                System.println("[Comm] Exercise at index " + i + " is not a Dictionary, skipping");
                continue;
            }
            var ex = _deserializeExercise(exDict as Dictionary);
            if (ex != null) {
                exercises.add(ex);
            }
        }

        if (exercises.size() == 0) {
            System.println("[Comm] No valid exercises in payload");
            return null;
        }

        return new Workout(id.toString(), name.toString(), exercises);
    }

    // Deserializes a single exercise Dictionary into an Exercise domain object.
    // Returns null if any required field is missing.
    private function _deserializeExercise(dict as Dictionary) as Exercise or Null {
        var name   = dict["name"];
        var sets   = dict["sets"];
        var reps   = dict["reps"];
        var weight = dict["weight"];
        var rest   = dict["rest"];

        if (name == null || sets == null || reps == null || weight == null || rest == null) {
            System.println("[Comm] Exercise missing required fields, skipping");
            return null;
        }

        return new Exercise(
            name.toString(),
            sets.toNumber(),
            reps.toNumber(),
            weight.toFloat(),
            rest.toNumber()
        );
    }

}
