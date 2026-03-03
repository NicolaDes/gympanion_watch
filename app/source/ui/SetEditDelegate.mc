import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;

// SetEditDelegate: handles button input on the SetEditView.
// Sequential field editing: weight first (UP/DOWN + START), then reps (UP/DOWN + START).
// BACK cancels without recording.
class SetEditDelegate extends WatchUi.BehaviorDelegate {

    private var _engine  as WorkoutEngine;
    private var _view    as SetEditView;

    private const WEIGHT_STEP = 2.5f;
    private const REPS_STEP   = 1;
    private const MIN_WEIGHT  = 0.0f;
    private const MIN_REPS    = 0;

    function initialize(engine as WorkoutEngine, view as SetEditView) {
        BehaviorDelegate.initialize();
        _engine = engine;
        _view   = view;
    }

    // UP button: increment the currently active field.
    function onPreviousPage() as Boolean {
        if (_view.editField == FIELD_WEIGHT) {
            _view.editWeight = _view.editWeight + WEIGHT_STEP;
        } else {
            _view.editReps = _view.editReps + REPS_STEP;
        }
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN button: decrement the currently active field, respecting minimums.
    function onNextPage() as Boolean {
        if (_view.editField == FIELD_WEIGHT) {
            var newWeight = _view.editWeight - WEIGHT_STEP;
            if (newWeight < MIN_WEIGHT) { newWeight = MIN_WEIGHT; }
            _view.editWeight = newWeight;
        } else {
            var newReps = _view.editReps - REPS_STEP;
            if (newReps < MIN_REPS) { newReps = MIN_REPS; }
            _view.editReps = newReps;
        }
        WatchUi.requestUpdate();
        return true;
    }

    // START button:
    //   On weight field: advance to reps field.
    //   On reps field:   confirm and record the set, then pop back to dashboard.
    function onSelect() as Boolean {
        if (_view.editField == FIELD_WEIGHT) {
            _view.editField = FIELD_REPS;
            WatchUi.requestUpdate();
        } else {
            // Confirm: record the set and return to dashboard
            _engine.completeSet(_view.editWeight, _view.editReps);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    // BACK button: cancel without recording. Engine restarts work phase.
    function onBack() as Boolean {
        _engine.cancelSet();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

}
