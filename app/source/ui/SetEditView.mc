import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;

// Field edit enum constants for SetEditView / SetEditDelegate
const FIELD_WEIGHT = 0;
const FIELD_REPS   = 1;

// SetEditView: pushed on top of DashboardView after the user marks a set done.
// Allows the user to confirm or adjust weight and reps before recording.
// Uses sequential field editing: weight first, then reps.
//
// All y-positions are computed at runtime via dc.getFontHeight() to eliminate
// hardcoded coordinate assumptions. A y cursor accumulates downward from the
// top of the safe zone (y=42), advancing by each element's actual font height
// plus explicit gap constants.
//
// Gap constants:
//   GAP_TITLE_TO_CARD  = 8   — space from title bottom to first card top
//   GAP_BETWEEN_CARDS  = 10  — space between weight card and reps card
//   CARD_PAD           = 6   — padding inside card top and bottom
//   GAP_INNER          = 4   — space between label and value inside card
//
// Fonts used:
//   Title       : FONT_SMALL
//   Card labels : FONT_XTINY
//   Card values : FONT_NUMBER_MILD
//
// Draw order per card: fillRoundedRectangle → label → value
// Active card  : COLOR_BLUE bg,    COLOR_WHITE  label + value
// Inactive card: COLOR_DK_GRAY bg, COLOR_LT_GRAY label + value
class SetEditView extends WatchUi.View {

    private var _engine     as WorkoutEngine;
    var editWeight          as Float;
    var editReps            as Number;
    var editField           as Number; // FIELD_WEIGHT or FIELD_REPS

    function initialize(engine as WorkoutEngine, defaultWeight as Float, defaultReps as Number) {
        View.initialize();
        _engine    = engine;
        editWeight = defaultWeight;
        editReps   = defaultReps;
        editField  = FIELD_WEIGHT;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // No XML layout. All drawing in onUpdate().
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var screenW = dc.getWidth();
        var centerX = screenW / 2;

        // Determine current exercise info for title
        var state   = _engine.getCurrentState();
        var workout = _engine.getWorkout();
        var setLabel = "Log Set";
        if (state != null && workout != null) {
            var ex    = null;
            var exIdx = state.currentExerciseIndex;
            if (workout.exercises != null && exIdx < workout.exercises.size()) {
                ex = workout.exercises[exIdx] as Exercise;
            }
            var totalSets = ex != null ? ex.targetSets : 0;
            setLabel = "Set " + (state.currentSetIndex + 1).toString() + " / " + totalSets.toString();
        }

        // Clear background — pure AMOLED black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ── Runtime font heights ─────────────────────────────────────────────
        var hSmall  = dc.getFontHeight(Graphics.FONT_SMALL);
        var hXtiny  = dc.getFontHeight(Graphics.FONT_XTINY);
        var hValue  = dc.getFontHeight(Graphics.FONT_NUMBER_MILD);

        // ── Gap/padding constants ────────────────────────────────────────────
        var GAP_TITLE_TO_CARD = 8;
        var GAP_BETWEEN_CARDS = 10;
        var GAP_HINT          = 8;
        var CARD_PAD          = 6;
        var GAP_INNER         = 4; // between label and value inside card

        // ── Card height derived from actual font heights ──────────────────────
        var cardH = CARD_PAD + hXtiny + GAP_INNER + hValue + CARD_PAD;

        // ── Card shared geometry ─────────────────────────────────────────────
        var cardX = 25;
        var cardW = screenW - 50; // 210px for 260-wide screen
        var cardR = 8;            // corner radius

        // ── y cursor — accumulates from top of safe zone ─────────────────────
        var y = 42;

        // Title row
        var y_title = y;
        y += hSmall + GAP_TITLE_TO_CARD;

        // Weight card
        var cardY1   = y;
        var y_wLabel = cardY1 + CARD_PAD;
        var y_wValue = y_wLabel + hXtiny + GAP_INNER;
        y += cardH + GAP_BETWEEN_CARDS;

        // Reps card
        var cardY2   = y;
        var y_rLabel = cardY2 + CARD_PAD;
        var y_rValue = y_rLabel + hXtiny + GAP_INNER;
        y += cardH + GAP_HINT;

        // Hint text
        var y_hint = y;

        // ── Title ────────────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_title, Graphics.FONT_SMALL,
                    setLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Weight card ──────────────────────────────────────────────────────
        var weightStr     = editWeight.format("%.1f") + " kg";
        var weightActive  = (editField == FIELD_WEIGHT);
        var weightBgColor = weightActive ? Graphics.COLOR_BLUE    : Graphics.COLOR_DK_GRAY;
        var weightFgColor = weightActive ? Graphics.COLOR_WHITE   : Graphics.COLOR_LT_GRAY;

        // 1) Card background
        dc.setColor(weightBgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY1, cardW, cardH, cardR);

        // 2) "WEIGHT" label
        dc.setColor(weightFgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_wLabel, Graphics.FONT_XTINY,
                    "WEIGHT", Graphics.TEXT_JUSTIFY_CENTER);

        // 3) Weight value
        dc.setColor(weightFgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_wValue, Graphics.FONT_NUMBER_MILD,
                    weightStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Reps card ────────────────────────────────────────────────────────
        var repsStr     = editReps.toString();
        var repsActive  = (editField == FIELD_REPS);
        var repsBgColor = repsActive ? Graphics.COLOR_BLUE    : Graphics.COLOR_DK_GRAY;
        var repsFgColor = repsActive ? Graphics.COLOR_WHITE   : Graphics.COLOR_LT_GRAY;

        // 1) Card background
        dc.setColor(repsBgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY2, cardW, cardH, cardR);

        // 2) "REPS" label
        dc.setColor(repsFgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_rLabel, Graphics.FONT_XTINY,
                    "REPS", Graphics.TEXT_JUSTIFY_CENTER);

        // 3) Reps value
        dc.setColor(repsFgColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_rValue, Graphics.FONT_NUMBER_MILD,
                    repsStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ── Hint text ────────────────────────────────────────────────────────
        var hint = "";
        if (editField == FIELD_WEIGHT) {
            hint = "UP/DOWN adj  START: next";
        } else {
            hint = "UP/DOWN adj  START: save";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_hint, Graphics.FONT_XTINY,
                    hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
