import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// NoOpConnectionListener: satisfies the Communications.transmit() requirement
// for a non-null ConnectionListener. Used for fire-and-forget phone messages
// where no acknowledgement is needed.
class NoOpConnectionListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() as Void {}
    function onError() as Void {
        System.println("[Comm] transmit error (no phone or companion protocol mismatch)");
    }
}

// CompanionCommService: Manages phone-to-watch communication via the
// Toybox.Communications API. Receives workout payloads from the companion
// app, deserializes them into domain objects, persists them, and notifies
// the WorkoutEngine to restart with the new workout.
//
// Also sends fire-and-forget set-complete notifications to the companion app
// via sendSetComplete() so the phone can prompt for actual weight/reps logged.
//
// Call startListening() once during app startup (in onStart).
// The system invokes onMessageReceived() whenever the companion app sends
// a message to this watch app.
class CompanionCommService {

    private var _engine as WorkoutEngine;
    private var _persistenceService as PersistenceService;
    private var _listener as NoOpConnectionListener;
    private var _pendingWorkout    as Workout or Null;
    private var _pendingWorkoutDict as Dictionary or Null;
    private var _onWorkoutAccepted as Method or Null;

    function initialize(engine as WorkoutEngine, persistenceService as PersistenceService) {
        _engine = engine;
        _persistenceService = persistenceService;
        _listener = new NoOpConnectionListener();
        _pendingWorkout     = null;
        _pendingWorkoutDict = null;
        _onWorkoutAccepted  = null;
    }

    // Sends a fire-and-forget set-complete notification to the companion phone app.
    // payload is a Dictionary with set metadata (exercise name, set/exercise indices,
    // duration, target weight/reps). No response is expected.
    //
    // When no phone is connected (e.g. simulator without ADB) the payload is
    // printed to the log instead of transmitted, avoiding the ADB error dialog.
    function sendSetComplete(payload as Dictionary) as Void {
        if (!(Communications has :transmit)) {
            System.println("[Comm] transmit not available on this device");
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            System.println("[Comm] No phone — set_complete payload: " + payload.toString());
            return;
        }
        Communications.transmit(payload, null, _listener);
        System.println("[Comm] Set complete sent to phone");
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

    // Registers a callback invoked after a pending workout is accepted and applied.
    // Used by gympApp to rebuild the summary menu with the new workout.
    // callback takes no arguments.
    function setOnWorkoutAccepted(callback as Method) as Void {
        _onWorkoutAccepted = callback;
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

        // Store pending workout (not applied until user confirms)
        _pendingWorkout     = workout;
        _pendingWorkoutDict = dict;

        // Show confirmation dialog on top of whatever view is currently active
        var msg2 = WatchUi.loadResource(Rez.Strings.workoutReplaceConfirmMsg) as String;
        var dialog = new WatchUi.Confirmation(msg2);
        WatchUi.pushView(dialog, new WorkoutReplaceConfirmDelegate(self), WatchUi.SLIDE_UP);
        System.println("[Comm] Pending workout stored, confirmation dialog shown");
    }

    // Called by WorkoutReplaceConfirmDelegate when the user chooses Replace.
    // Persists, applies the pending workout, notifies the phone, and fires
    // the onWorkoutAccepted callback so the summary menu can be rebuilt.
    function acceptPendingWorkout() as Void {
        if (_pendingWorkout == null || _pendingWorkoutDict == null) { return; }

        // Persist and apply
        _persistenceService.saveCompanionWorkout(_pendingWorkoutDict);
        _persistenceService.clearSession();
        _engine.setWorkout(_pendingWorkout);
        _engine.startNewSession(_pendingWorkout);

        // Notify phone
        _sendWorkoutReplaceResponse(true);

        // Notify gympApp to rebuild summary menu
        if (_onWorkoutAccepted != null) {
            _onWorkoutAccepted.invoke();
        }

        System.println("[Comm] Pending workout accepted: " + _pendingWorkout.name);

        // Clear pending state
        _pendingWorkout     = null;
        _pendingWorkoutDict = null;

        WatchUi.requestUpdate();
    }

    // Called by WorkoutReplaceConfirmDelegate when the user chooses Discard.
    // Notifies the phone and clears the pending workout without applying it.
    function discardPendingWorkout() as Void {
        _sendWorkoutReplaceResponse(false);
        _pendingWorkout     = null;
        _pendingWorkoutDict = null;
        System.println("[Comm] Pending workout discarded");
    }

    // Sends a fire-and-forget workout replace response to the companion phone app.
    // accepted: true if the user chose Replace, false if they chose Discard.
    private function _sendWorkoutReplaceResponse(accepted as Boolean) as Void {
        var payload = {
            "type"     => "workout_replace_response",
            "accepted" => accepted
        };
        if (!(Communications has :transmit)) {
            System.println("[Comm] transmit not available: " + payload.toString());
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            System.println("[Comm] No phone — workout_replace_response: " + payload.toString());
            return;
        }
        Communications.transmit(payload, null, _listener);
        System.println("[Comm] workout_replace_response sent: accepted=" + accepted.toString());
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
