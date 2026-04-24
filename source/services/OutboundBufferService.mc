import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.Communications;
import Toybox.Application;

// OutboundBufferService owns the per-workout pending-outbound buffer and
// the flush state machine. It never touches Application.Storage directly —
// all I/O goes through PersistenceService. It never pushes WatchUi views —
// the popup is pushed by DashboardDelegate via the CompanionCommService
// onStorageFull callback.
class OutboundBufferService {

    // ─── Caps ────────────────────────────────────────────────────────────
    private const BYTE_BUDGET          = 32 * 1024;   // 32 KB soft cap
    private const MAX_WORKOUTS         = 10;          // hard guard
    private const MAX_SETS_PER_SESSION = 500;         // hard guard
    private const FLUSH_INTERVAL_MS    = 15000;       // 15 s poll
    private const FLUSH_DELAY_MS       = 250;         // per-send pacing

    // Per-set size estimate (bytes). The constant is approximate; if real
    // storage round-trips start failing at the 32 KB budget, lower BYTE_BUDGET.
    private const SET_SIZE_EST         = 220;
    // Per-session-header estimate (bytes).
    private const SESSION_HEADER_EST   = 128;

    // ─── Enqueue result symbols ─────────────────────────────────────────
    // Use symbols so callers can switch on them without stringly-typed checks.
    // :enqueued      -> payload written to storage
    // :skippedGiveUp -> session is in the give-up set; caller drops payload
    // :needsPopup    -> caller must push StorageFullMenuDelegate
    // :enqueuedFirst -> first item in an empty buffer (caller may kick flush)

    // ─── Dependencies ────────────────────────────────────────────────────
    private var _persistence  as PersistenceService;
    private var _commService  as CompanionCommService or Null;  // late-bound

    // ─── Flush state ─────────────────────────────────────────────────────
    private var _flushing          as Boolean;
    private var _pollTimer         as Timer.Timer or Null;
    private var _continuationTimer as Timer.Timer or Null;
    private var _currentSessionKey as String or Null;
    private var _currentSetIndex   as Number;
    private var _currentPhase      as Symbol;   // :sets | :result | :done

    function initialize(persistence as PersistenceService) {
        _persistence        = persistence;
        _commService        = null;
        _flushing           = false;
        _pollTimer          = null;
        _continuationTimer  = null;
        _currentSessionKey  = null;
        _currentSetIndex    = 0;
        _currentPhase       = :sets;
    }

    // Late-bound to break the init cycle with CompanionCommService.
    // Call once in gympApp.initialize() after both services are constructed.
    function setCommService(comm as CompanionCommService) as Void {
        _commService = comm;
    }

    // ─── Give-up API ─────────────────────────────────────────────────────

    // True iff the session has been marked give-up by the user.
    function isGiveUp(sessionId as String) as Boolean {
        var g = _persistence.loadGiveUpSessions();
        return g.hasKey(sessionId) && g[sessionId] == true;
    }

    // Marks the session give-up. Future enqueues for that sessionId return
    // :skippedGiveUp. Called only by resolveFull_dontStore() (Step 6).
    private function _markGiveUp(sessionId as String) as Void {
        var g = _persistence.loadGiveUpSessions();
        g.put(sessionId, true);
        _persistence.saveGiveUpSessions(g);
    }

    // Clears the give-up flag for a session. Called when the session's group
    // is successfully flushed, or by housekeeping at app start.
    private function _clearGiveUp(sessionId as String) as Void {
        var g = _persistence.loadGiveUpSessions();
        if (g.hasKey(sessionId)) {
            g.remove(sessionId);
            _persistence.saveGiveUpSessions(g);
        }
    }

    // On-start housekeeping: drop give-up entries whose sessionId no longer
    // appears in pending_outbound. Prevents the give-up map from growing
    // across months of normal use.
    function pruneOrphanGiveUpEntries() as Void {
        var g = _persistence.loadGiveUpSessions();
        if (g.size() == 0) { return; }
        var buf = _persistence.loadPendingOutbound();
        var gKeys = g.keys();
        var changed = false;
        for (var i = 0; i < gKeys.size(); i++) {
            var sid = gKeys[i] as String;
            if (!buf.hasKey(sid)) {
                g.remove(sid);
                changed = true;
            }
        }
        if (changed) {
            _persistence.saveGiveUpSessions(g);
        }
    }

    // Estimates the serialized size of the buffer dict in bytes. Cheap
    // approximation — avoids stringifying the whole dict on every append.
    private function _estimateSize(buf as Dictionary) as Number {
        var total = 0;
        var keys = buf.keys();
        for (var i = 0; i < keys.size(); i++) {
            var group = buf[keys[i]] as Dictionary;
            total += SESSION_HEADER_EST;
            var name = group["workoutName"];
            if (name != null && name instanceof String) {
                total += (name as String).length();
            }
            var sets = group["sets"];
            if (sets != null && sets instanceof Array) {
                total += (sets as Array).size() * SET_SIZE_EST;
            }
            var sr = group["sessionResult"];
            if (sr != null && sr instanceof Dictionary) {
                total += _estimateSessionResultSize(sr as Dictionary);
            }
        }
        return total;
    }

    // Walks a session_result dict and sums estimated entry sizes without
    // serializing. Structure: { blocks: [ { type, ..., sets | rounds } ] }.
    private function _estimateSessionResultSize(sr as Dictionary) as Number {
        var total = 256;  // outer envelope overhead
        var blocks = sr["blocks"];
        if (blocks == null || !(blocks instanceof Array)) { return total; }
        var blocksArr = blocks as Array;
        for (var i = 0; i < blocksArr.size(); i++) {
            var b = blocksArr[i] as Dictionary;
            total += 96;  // per-block header
            var type = b["type"];
            if (type != null && type.toString().equals("sequential")) {
                var exs = b["exercises"];
                if (exs != null && exs instanceof Array) {
                    var exArr = exs as Array;
                    for (var j = 0; j < exArr.size(); j++) {
                        var ex = exArr[j] as Dictionary;
                        var exSets = ex["sets"];
                        if (exSets != null && exSets instanceof Array) {
                            total += (exSets as Array).size() * SET_SIZE_EST;
                        }
                        total += 48;
                    }
                }
            } else {
                // emom / amrap: rounds -> sets
                var rounds = b["rounds"];
                if (rounds != null && rounds instanceof Array) {
                    var rArr = rounds as Array;
                    for (var k = 0; k < rArr.size(); k++) {
                        var r = rArr[k] as Dictionary;
                        var rSets = r["sets"];
                        if (rSets != null && rSets instanceof Array) {
                            total += (rSets as Array).size() * SET_SIZE_EST;
                        }
                        total += 48;
                    }
                }
            }
        }
        return total;
    }

    // ─── Public API (implemented in later steps) ─────────────────────────

    function enqueue(payload as Dictionary, sessionMeta as Dictionary) as Symbol {
        var sessionId = sessionMeta["sessionId"] as String;

        // Give-up sessions short-circuit: caller drops payload silently.
        if (isGiveUp(sessionId)) {
            return :skippedGiveUp;
        }

        var buf = _persistence.loadPendingOutbound();

        // Build-or-get the session group.
        var group;
        if (buf.hasKey(sessionId)) {
            group = buf[sessionId] as Dictionary;
        } else {
            group = {
                "workoutId"     => sessionMeta["workoutId"],
                "workoutName"   => sessionMeta["workoutName"],
                "startedAt"     => sessionMeta["startedAt"],
                "nextSeq"       => 0,
                "sets"          => new [0],
                "sessionResult" => null
            };
        }

        // Cap checks: compute prospective post-append size.
        var payloadType = payload["type"].toString();
        var isSetComplete = payloadType.equals("set_complete");
        var isSessionResult = payloadType.equals("session_result");

        // Hard guard: max sets per session.
        if (isSetComplete) {
            var existingSets = (group["sets"] as Array).size();
            if (existingSets >= MAX_SETS_PER_SESSION) {
                System.println("[Buffer] Hard cap: max sets per session");
                return :needsPopup;
            }
        }

        // Hard guard: max workouts. Only relevant for brand-new sessionIds.
        if (!buf.hasKey(sessionId) && buf.size() >= MAX_WORKOUTS) {
            System.println("[Buffer] Hard cap: max workouts");
            return :needsPopup;
        }

        // Soft guard: 32 KB total. Build a mutated copy for estimation.
        var prospective = _cloneDictShallow(buf);
        var prospectiveGroup = _cloneGroupForEstimate(group);
        if (isSetComplete) {
            var sets = prospectiveGroup["sets"] as Array;
            sets.add(payload);
        } else if (isSessionResult) {
            prospectiveGroup["sessionResult"] = payload;
        }
        prospective.put(sessionId, prospectiveGroup);
        if (_estimateSize(prospective) > BYTE_BUDGET) {
            System.println("[Buffer] Soft cap: byte budget (" + _estimateSize(prospective) + " B)");
            return :needsPopup;
        }

        // All caps passed — commit the mutation.
        var nextSeq = (group["nextSeq"] as Number);
        if (isSetComplete) {
            payload.put("seq", nextSeq);
            (group["sets"] as Array).add(payload);
            group.put("nextSeq", nextSeq + 1);
        } else if (isSessionResult) {
            group.put("sessionResult", payload);
        } else {
            System.println("[Buffer] Unknown payload type: " + payloadType);
            return :enqueued;  // shouldn't happen, but don't fail the live path
        }
        buf.put(sessionId, group);
        _persistence.savePendingOutbound(buf);

        return :enqueued;
    }

    // Shallow clone — keys copied but values (inner dicts) shared by reference.
    // Adequate for the prospective-size estimate because we only mutate the
    // one group and we restore via group clone below.
    private function _cloneDictShallow(d as Dictionary) as Dictionary {
        var out = {};
        var keys = d.keys();
        for (var i = 0; i < keys.size(); i++) {
            out.put(keys[i], d[keys[i]]);
        }
        return out;
    }

    // Clones a session group's `sets` array so estimation-time `.add()` does
    // not mutate the real in-storage group. Other fields can be shared.
    private function _cloneGroupForEstimate(group as Dictionary) as Dictionary {
        var out = _cloneDictShallow(group);
        var sets = group["sets"];
        if (sets instanceof Array) {
            var copy = new [0];
            var arr = sets as Array;
            for (var i = 0; i < arr.size(); i++) {
                copy.add(arr[i]);
            }
            out.put("sets", copy);
        }
        return out;
    }

    function resolveFull_deleteOldest(
        payload as Dictionary, sessionMeta as Dictionary
    ) as Void {
        var currentId = sessionMeta["sessionId"] as String;
        var buf = _persistence.loadPendingOutbound();

        // Find the oldest session that is NOT the current one.
        var oldestKey = null;
        var oldestStart = 2147483647;   // large sentinel
        var keys = buf.keys();
        for (var i = 0; i < keys.size(); i++) {
            var k = keys[i] as String;
            if (k.equals(currentId)) { continue; }
            var s = ((buf[k] as Dictionary)["startedAt"]) as Number;
            if (s < oldestStart) {
                oldestStart = s;
                oldestKey = k;
            }
        }

        if (oldestKey == null) {
            // Nothing else to evict — the UI should have disabled this option,
            // but handle defensively: fall through to give-up.
            System.println("[Buffer] resolveFull_deleteOldest: no evictable session");
            _markGiveUp(currentId);
            return;
        }

        buf.remove(oldestKey);
        _clearGiveUp(oldestKey as String);
        _persistence.savePendingOutbound(buf);
        System.println("[Buffer] Evicted oldest session: " + oldestKey);

        // Retry the original enqueue. If it still won't fit, drop silently —
        // do not re-show the popup (spec §11.4).
        var result = enqueue(payload, sessionMeta);
        if (result != :enqueued) {
            System.println("[Buffer] Post-eviction enqueue still failed: "
                + result.toString() + " — dropping");
        }
    }

    function resolveFull_dontStore(sessionId as String) as Void {
        _markGiveUp(sessionId);
        System.println("[Buffer] Session marked give-up: " + sessionId);
    }

    // Single ConnectionListener for replay sends. Unlike the live listener,
    // it does NOT kick another flush on onComplete — the state-machine
    // continuation timer drives the next send.
    private var _replayListener as Communications.ConnectionListener or Null;

    function flushIfPossible() as Void {
        if (_flushing) { return; }

        if (!System.getDeviceSettings().phoneConnected) {
            if (hasPending()) { _ensurePollTimer(); }
            return;
        }

        var buf = _persistence.loadPendingOutbound();
        if (buf.size() == 0) {
            _stopPollTimer();
            return;
        }

        _flushing = true;
        _ensurePollTimer();
        _pickNextGroup(buf);
        if (_currentSessionKey == null) {
            _flushing = false;
            _stopPollTimer();
            return;
        }
        _currentSetIndex = 0;
        _currentPhase = :sets;
        _sendNextPayload();
    }

    // Picks the session group with the smallest startedAt and stores its
    // key in _currentSessionKey.
    private function _pickNextGroup(buf as Dictionary) as Void {
        var keys = buf.keys();
        if (keys.size() == 0) {
            _currentSessionKey = null;
            return;
        }
        var bestKey = keys[0] as String;
        var bestStart = ((buf[bestKey] as Dictionary)["startedAt"]) as Number;
        for (var i = 1; i < keys.size(); i++) {
            var k = keys[i] as String;
            var s = ((buf[k] as Dictionary)["startedAt"]) as Number;
            if (s < bestStart) {
                bestStart = s;
                bestKey = k;
            }
        }
        _currentSessionKey = bestKey;
    }

    // Core state-machine step. Invoked from flushIfPossible() and from the
    // continuation timer. At the end of each transmit it schedules itself
    // again 250 ms later.
    function _sendNextPayload() as Void {
        if (_currentSessionKey == null) {
            _finishFlush();
            return;
        }

        // Verify phone still connected between sends.
        if (!System.getDeviceSettings().phoneConnected) {
            _abortFlush();
            return;
        }

        var buf = _persistence.loadPendingOutbound();
        if (!buf.hasKey(_currentSessionKey)) {
            // Group was removed (race with user action). Move on.
            _pickNextGroup(buf);
            if (_currentSessionKey == null) { _finishFlush(); return; }
            _currentSetIndex = 0;
            _currentPhase = :sets;
            _scheduleContinuation();
            return;
        }
        var group = buf[_currentSessionKey] as Dictionary;

        if (_currentPhase == :sets) {
            var sets = group["sets"] as Array;
            if (_currentSetIndex < sets.size()) {
                var payload = sets[_currentSetIndex] as Dictionary;
                if (_replayListener == null) {
                    _replayListener = new ReplayConnectionListener(self);
                }
                try {
                    Communications.transmit(payload, null, _replayListener);
                } catch (e instanceof Lang.Exception) {
                    System.println("[Buffer] replay transmit failed: " + e.getErrorMessage());
                    _abortFlush();
                    return;
                }
                _currentSetIndex += 1;
                _scheduleContinuation();
                return;
            } else {
                _currentPhase = :result;
                _sendNextPayload();  // tail-style recursion, depth == 1
                return;
            }
        }

        if (_currentPhase == :result) {
            var sr = group["sessionResult"];
            if (sr != null && sr instanceof Dictionary) {
                if (_replayListener == null) {
                    _replayListener = new ReplayConnectionListener(self);
                }
                try {
                    Communications.transmit(sr as Dictionary, null, _replayListener);
                } catch (e instanceof Lang.Exception) {
                    System.println("[Buffer] replay transmit failed: " + e.getErrorMessage());
                    _abortFlush();
                    return;
                }
                _currentPhase = :done;
                _scheduleContinuation();
                return;
            } else {
                _currentPhase = :done;
                _sendNextPayload();
                return;
            }
        }

        if (_currentPhase == :done) {
            // Remove the group, clear any give-up flag, move on.
            buf.remove(_currentSessionKey);
            _persistence.savePendingOutbound(buf);
            _clearGiveUp(_currentSessionKey as String);
            System.println("[Buffer] Flushed session: " + _currentSessionKey);

            _pickNextGroup(buf);
            if (_currentSessionKey == null) {
                _finishFlush();
                return;
            }
            _currentSetIndex = 0;
            _currentPhase = :sets;
            _scheduleContinuation();
            return;
        }
    }

    // Called by ReplayConnectionListener.onError — stops the flush without
    // removing the current group from storage. Next trigger retries.
    function _onReplayError() as Void {
        System.println("[Buffer] Replay onError — aborting flush");
        _abortFlush();
    }

    private function _abortFlush() as Void {
        if (_continuationTimer != null) {
            _continuationTimer.stop();
            _continuationTimer = null;
        }
        _flushing = false;
        _currentSessionKey = null;
        // Poll timer stays running — it will retry on the next 15-s tick.
    }

    private function _finishFlush() as Void {
        _flushing = false;
        _currentSessionKey = null;
        if (_continuationTimer != null) {
            _continuationTimer.stop();
            _continuationTimer = null;
        }
        if (!hasPending()) {
            _stopPollTimer();
        }
    }

    private function _scheduleContinuation() as Void {
        if (_continuationTimer != null) {
            _continuationTimer.stop();
        }
        _continuationTimer = new Timer.Timer();
        _continuationTimer.start(method(:_sendNextPayload), FLUSH_DELAY_MS, false);
    }

    private function _ensurePollTimer() as Void {
        if (_pollTimer != null) { return; }
        _pollTimer = new Timer.Timer();
        _pollTimer.start(method(:flushIfPossible), FLUSH_INTERVAL_MS, true);
        System.println("[Buffer] Poll timer started");
    }

    private function _stopPollTimer() as Void {
        if (_pollTimer != null) {
            _pollTimer.stop();
            _pollTimer = null;
            System.println("[Buffer] Poll timer stopped");
        }
    }

    function hasPending() as Boolean {
        var buf = _persistence.loadPendingOutbound();
        return buf.size() > 0;
    }

    function pendingWorkoutCount() as Number {
        return _persistence.loadPendingOutbound().size();
    }

    // True iff the oldest buffered session (by startedAt) is `currentSessionId`.
    // Used by the UI to disable "Delete oldest workout" when it would evict
    // the currently-recording session.
    function oldestIsCurrent(currentSessionId as String) as Boolean {
        var buf = _persistence.loadPendingOutbound();
        var keys = buf.keys();
        if (keys.size() == 0) { return false; }
        var oldestKey = keys[0] as String;
        var oldestStart = ((buf[oldestKey] as Dictionary)["startedAt"]) as Number;
        for (var i = 1; i < keys.size(); i++) {
            var k = keys[i] as String;
            var s = ((buf[k] as Dictionary)["startedAt"]) as Number;
            if (s < oldestStart) {
                oldestStart = s;
                oldestKey = k;
            }
        }
        return oldestKey.equals(currentSessionId);
    }
}

// Replay-only ConnectionListener. Forwards onComplete to the state-machine
// continuation (via the 250 ms timer already scheduled) and onError to
// OutboundBufferService._onReplayError() so the flush aborts cleanly.
class ReplayConnectionListener extends Communications.ConnectionListener {
    private var _svc as OutboundBufferService;
    function initialize(svc as OutboundBufferService) {
        ConnectionListener.initialize();
        _svc = svc;
    }
    function onComplete() as Void {
        // No-op — continuation is already scheduled by _scheduleContinuation().
    }
    function onError() as Void {
        _svc._onReplayError();
    }
}
