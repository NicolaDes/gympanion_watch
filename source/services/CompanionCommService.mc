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
    private var _buffer as OutboundBufferService;
    private var _liveListener as FlushKickingConnectionListener;
    private var _errorListener as NoOpConnectionListener;  // for error-response sends
    private var _pendingWorkout    as Workout or Null;
    private var _pendingWorkoutDict as Dictionary or Null;
    private var _onWorkoutAccepted as Method or Null;
    private var _onStorageFull     as Method or Null;

    function initialize(
        engine as WorkoutEngine,
        persistenceService as PersistenceService,
        buffer as OutboundBufferService
    ) {
        _engine = engine;
        _persistenceService = persistenceService;
        _buffer = buffer;
        _liveListener = new FlushKickingConnectionListener(buffer);
        _errorListener = new NoOpConnectionListener();
        _pendingWorkout     = null;
        _pendingWorkoutDict = null;
        _onWorkoutAccepted  = null;
        _onStorageFull      = null;
    }

    // Registers a callback invoked when the buffer is full and a payload
    // would be dropped. Callback signature:
    //   callback(payload as Dictionary, sessionMeta as Dictionary) -> Void
    // DashboardDelegate uses this to push the StorageFullMenuDelegate view.
    function setOnStorageFull(callback as Method) as Void {
        _onStorageFull = callback;
    }

    // Sends a set_complete notification to the companion phone app.
    //   payload:     the set_complete dict (must already include sessionId).
    //   sessionMeta: { sessionId, workoutId, workoutName, startedAt }.
    // Always attempts to enqueue into OutboundBuffer before live transmit.
    // If the buffer is full, the onStorageFull callback is invoked to push
    // the popup; live transmit is still attempted regardless.
    function sendSetComplete(payload as Dictionary, sessionMeta as Dictionary) as Void {
        var res = _buffer.enqueue(payload, sessionMeta);
        if (res == :needsPopup && _onStorageFull != null) {
            _onStorageFull.invoke(payload, sessionMeta);
        }
        if (res == :skippedGiveUp) {
            // Give-up session: still attempt live transmission but don't buffer.
        }
        _transmitLive(payload);
    }

    // Sends a session_result envelope to the companion phone app. Same
    // enqueue-then-transmit flow as sendSetComplete.
    function sendSessionResult(resultPayload as Dictionary, sessionMeta as Dictionary) as Void {
        var res = _buffer.enqueue(resultPayload, sessionMeta);
        if (res == :needsPopup && _onStorageFull != null) {
            _onStorageFull.invoke(resultPayload, sessionMeta);
        }
        _transmitLive(resultPayload);
    }

    // Live-path transmit, shared by sendSetComplete and sendSessionResult.
    private function _transmitLive(payload as Dictionary) as Void {
        if (!(Communications has :transmit)) {
            System.println("[Comm] transmit not available on this device");
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            System.println("[Comm] No phone — payload will be replayed on reconnect: "
                + payload["type"].toString());
            return;
        }
        try {
            Communications.transmit(payload, null, _liveListener);
            System.println("[Comm] live " + payload["type"].toString() + " sent");
        } catch (e instanceof Lang.Exception) {
            System.println("[Comm] transmit failed: " + e.getErrorMessage());
        }
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

        // Check version — reject unsupported versions
        var version = dict["v"];
        if (version != null && version.toNumber() > 2) {
            System.println("[Comm] Unsupported payload version: " + version.toString());
            _sendErrorResponse("unsupported_version", 2);
            return;
        }

        // Route by message type (v2) or fall back to workout assumption (v1)
        var msgType = dict["type"];
        if (msgType != null && msgType.toString().equals("workout")) {
            _handleWorkoutMessage(dict);
        } else if (msgType == null) {
            // v1 payload — no type field, assume workout
            _handleWorkoutMessage(dict);
        } else {
            System.println("[Comm] Unknown message type: " + msgType.toString());
        }
    }

    private function _handleWorkoutMessage(dict as Dictionary) as Void {
        var workout = deserializeWorkout(dict);
        if (workout == null) {
            System.println("[Comm] Failed to deserialize workout");
            return;
        }

        _pendingWorkout     = workout;
        _pendingWorkoutDict = dict;

        var msg2 = WatchUi.loadResource(Rez.Strings.workoutReplaceConfirmMsg) as String;
        var dialog = new WatchUi.Confirmation(msg2);
        WatchUi.pushView(dialog, new WorkoutReplaceConfirmDelegate(self), WatchUi.SLIDE_UP);
        System.println("[Comm] Pending workout stored, confirmation dialog shown");
    }

    private function _sendErrorResponse(code as String, maxSupported as Number) as Void {
        var payload = {
            "type"         => "error",
            "code"         => code,
            "maxSupported" => maxSupported
        };
        if (!(Communications has :transmit)) { return; }
        if (!System.getDeviceSettings().phoneConnected) {
            System.println("[Comm] No phone — error response: " + payload.toString());
            return;
        }
        try {
            Communications.transmit(payload, null, _errorListener);
        } catch (e instanceof Lang.Exception) {
            System.println("[Comm] transmit failed: " + e.getErrorMessage());
        }
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
        try {
            Communications.transmit(payload, null, _errorListener);
            System.println("[Comm] workout_replace_response sent: accepted=" + accepted.toString());
        } catch (e instanceof Lang.Exception) {
            System.println("[Comm] transmit failed: " + e.getErrorMessage());
        }
    }

    // ─── Deserialization ─────────────────────────────────────────────────

    // Entry point: routes to v1 or v2 based on version field.
    // Public so gympApp.onStart() can re-deserialize stored companion workout
    // Dictionaries without duplicating this logic.
    function deserializeWorkout(dict as Dictionary) as Workout or Null {
        var version = dict["v"];
        if (version != null && version.toNumber() >= 2) {
            return _deserializeV2(dict);
        }
        return _deserializeV1(dict);
    }

    // V1 backward-compatible deserializer — wraps flat exercises in a single
    // sequential block for v2 engine compatibility.
    private function _deserializeV1(dict as Dictionary) as Workout or Null {
        var id           = dict["id"];
        var name         = dict["name"];
        var exercisesRaw = dict["exercises"];

        if (id == null || name == null || exercisesRaw == null) {
            System.println("[Comm] V1 Workout missing required top-level fields");
            return null;
        }
        if (!(exercisesRaw instanceof Array)) {
            System.println("[Comm] V1 'exercises' field is not an Array");
            return null;
        }

        var rawArray  = exercisesRaw as Array;
        var exercises = new [0];

        for (var i = 0; i < rawArray.size(); i++) {
            var exDict = rawArray[i];
            if (exDict == null || !(exDict instanceof Dictionary)) { continue; }
            var ex = _deserializeExercise(exDict as Dictionary);
            if (ex != null) { exercises.add(ex); }
        }

        if (exercises.size() == 0) {
            System.println("[Comm] V1: No valid exercises in payload");
            return null;
        }

        // Wrap in a single sequential block for v2 engine compatibility
        var block = new WorkoutBlock(BLOCK_SEQUENTIAL, "");
        block.exercises = exercises;

        return new Workout(id.toString(), name.toString(), [block], exercises);
    }

    // V2 deserializer: block-based workout
    private function _deserializeV2(dict as Dictionary) as Workout or Null {
        var id   = dict["id"];
        var name = dict["name"];
        var blocksRaw = dict["blocks"];

        if (id == null || name == null || blocksRaw == null) {
            System.println("[Comm] V2 workout missing required top-level fields");
            return null;
        }
        if (!(blocksRaw instanceof Array)) {
            System.println("[Comm] V2 'blocks' field is not an Array");
            return null;
        }

        var rawArray = blocksRaw as Array;
        var blocks = new [0];
        var allExercises = new [0];  // flattened for summary menu

        for (var i = 0; i < rawArray.size(); i++) {
            var blockDict = rawArray[i];
            if (blockDict == null || !(blockDict instanceof Dictionary)) {
                System.println("[Comm] Block at index " + i + " is not a Dictionary, skipping");
                continue;
            }
            var result = _deserializeBlock(blockDict as Dictionary, allExercises);
            if (result != null) {
                blocks.add(result);
            }
        }

        if (blocks.size() == 0) {
            System.println("[Comm] No valid blocks in V2 payload");
            return null;
        }

        return new Workout(id.toString(), name.toString(), blocks, allExercises);
    }

    // Dispatches to the correct block deserializer based on "type"
    private function _deserializeBlock(dict as Dictionary, allExercises as Array) as WorkoutBlock or Null {
        var type = dict["type"];
        if (type == null) {
            System.println("[Comm] Block missing 'type' field");
            return null;
        }
        var typeStr = type.toString();
        if (typeStr.equals("sequential")) {
            return _deserializeSequentialBlock(dict, allExercises);
        } else if (typeStr.equals("emom")) {
            return _deserializeEmomBlock(dict, allExercises);
        } else if (typeStr.equals("amrap")) {
            return _deserializeAmrapBlock(dict, allExercises);
        } else {
            System.println("[Comm] Unknown block type: " + typeStr);
            return null;
        }
    }

    // ─── Sequential block deserialization ────────────────────────────────

    private function _deserializeSequentialBlock(dict as Dictionary, allExercises as Array) as WorkoutBlock or Null {
        var blockName = dict["name"];
        var block = new WorkoutBlock(BLOCK_SEQUENTIAL, blockName != null ? blockName.toString() : "");

        var exercisesRaw = dict["exercises"];
        if (exercisesRaw == null || !(exercisesRaw instanceof Array)) {
            System.println("[Comm] Sequential block missing 'exercises' array");
            return null;
        }

        var exercises = new [0];
        var rawArray = exercisesRaw as Array;

        for (var i = 0; i < rawArray.size(); i++) {
            var exDict = rawArray[i];
            if (exDict == null || !(exDict instanceof Dictionary)) { continue; }
            var d = exDict as Dictionary;

            var exId   = d["id"];
            var exName = d["name"];
            var setsRaw = d["sets"];

            if (exName == null || setsRaw == null || !(setsRaw instanceof Array)) { continue; }

            var blockSets = _deserializeBlockSets(
                exId != null ? exId.toString() : "",
                exName.toString(),
                setsRaw as Array
            );

            if (blockSets.size() > 0) {
                var exercise = Exercise.fromBlockSets(
                    exId != null ? exId.toString() : "",
                    exName.toString(),
                    blockSets
                );
                exercises.add(exercise);
                allExercises.add(exercise);
            }
        }

        if (exercises.size() == 0) { return null; }
        block.exercises = exercises;
        return block;
    }

    // Deserializes an array of set dictionaries into BlockSet objects
    private function _deserializeBlockSets(exId as String, exName as String, rawSets as Array) as Array {
        var result = new [0];
        for (var i = 0; i < rawSets.size(); i++) {
            var setDict = rawSets[i];
            if (setDict == null || !(setDict instanceof Dictionary)) { continue; }
            var d = setDict as Dictionary;

            var si = d["si"];
            if (si == null) { continue; }

            var bs = new BlockSet(
                exId,
                exName,
                si.toNumber(),
                d["reps"] != null ? d["reps"].toNumber() : null,
                d["wKg"] != null ? d["wKg"].toFloat() : null,
                d["durSec"] != null ? d["durSec"].toNumber() : null,
                d["distM"] != null ? d["distM"].toFloat() : null,
                d["restSec"] != null ? d["restSec"].toNumber() : null
            );
            result.add(bs);
        }
        return result;
    }

    // ─── EMOM block deserialization ──────────────────────────────────────

    private function _deserializeEmomBlock(dict as Dictionary, allExercises as Array) as WorkoutBlock or Null {
        var blockName = dict["name"];
        var block = new WorkoutBlock(BLOCK_EMOM, blockName != null ? blockName.toString() : "");

        var intervalSec = dict["intervalSec"];
        if (intervalSec == null) {
            System.println("[Comm] EMOM block missing 'intervalSec'");
            return null;
        }
        block.intervalSec = intervalSec.toNumber();

        var roundsRaw = dict["rounds"];
        if (roundsRaw == null || !(roundsRaw instanceof Array)) {
            System.println("[Comm] EMOM block missing 'rounds' array");
            return null;
        }

        var rounds = new [0];
        var rawArray = roundsRaw as Array;

        for (var i = 0; i < rawArray.size(); i++) {
            var roundDict = rawArray[i];
            if (roundDict == null || !(roundDict instanceof Dictionary)) { continue; }
            var d = roundDict as Dictionary;

            var ri = d["ri"];
            if (ri == null) { continue; }

            var setsRaw = d["sets"];
            if (setsRaw == null || !(setsRaw instanceof Array)) { continue; }

            var roundSets = _deserializeEmomSets(setsRaw as Array);
            if (roundSets.size() > 0) {
                rounds.add(new EmomRound(ri.toNumber(), roundSets));
            }
        }

        if (rounds.size() == 0) { return null; }
        block.rounds = rounds;
        return block;
    }

    // Deserializes EMOM/AMRAP set entries (have exId instead of inheriting from parent exercise)
    private function _deserializeEmomSets(rawSets as Array) as Array {
        var result = new [0];
        for (var i = 0; i < rawSets.size(); i++) {
            var setDict = rawSets[i];
            if (setDict == null || !(setDict instanceof Dictionary)) { continue; }
            var d = setDict as Dictionary;

            var exId = d["exId"];
            var name = d["name"];
            if (name == null) { continue; }

            var bs = new BlockSet(
                exId != null ? exId.toString() : "",
                name.toString(),
                i,  // si = position within round
                d["reps"] != null ? d["reps"].toNumber() : null,
                d["wKg"] != null ? d["wKg"].toFloat() : null,
                d["durSec"] != null ? d["durSec"].toNumber() : null,
                d["distM"] != null ? d["distM"].toFloat() : null,
                null  // no restSec in EMOM — rest is time remaining in interval
            );
            result.add(bs);
        }
        return result;
    }

    // ─── AMRAP block deserialization ─────────────────────────────────────

    private function _deserializeAmrapBlock(dict as Dictionary, allExercises as Array) as WorkoutBlock or Null {
        var blockName = dict["name"];
        var block = new WorkoutBlock(BLOCK_AMRAP, blockName != null ? blockName.toString() : "");

        var timeCapSec = dict["timeCapSec"];
        if (timeCapSec == null) {
            System.println("[Comm] AMRAP block missing 'timeCapSec'");
            return null;
        }
        block.timeCapSec = timeCapSec.toNumber();

        var setsRaw = dict["sets"];
        if (setsRaw == null || !(setsRaw instanceof Array)) {
            System.println("[Comm] AMRAP block missing 'sets' array");
            return null;
        }

        // Reuse EMOM set deserializer — same shape (exId, name, reps, wKg, etc.)
        var sets = _deserializeEmomSets(setsRaw as Array);
        if (sets.size() == 0) { return null; }

        block.sets = sets;
        return block;
    }

    // ─── V1 exercise deserialization ─────────────────────────────────────

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
