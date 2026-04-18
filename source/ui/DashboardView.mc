import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;

// DashboardView: the primary screen of GymPanion.
// Custom-drawn (no XML layout) because the timer and heart rate update every second.
// Reads all state from WorkoutEngine on each onUpdate() call.
//
// All y-positions are computed at runtime via dc.getFontHeight() to eliminate
// hardcoded coordinate assumptions. A y cursor accumulates downward from the
// top of the safe zone (y=44), advancing by each element's actual font height
// plus an explicit gap constant.
//
// Gap constants:
//   GAP_SM = 4  — between most adjacent rows
//   GAP_MD = 6  — before/after divider lines
//   GAP_LG = 8  — above/below the timer (it is a large element)
//
// Fonts used (small enough for all elements to fit within 260px height):
//   Exercise name  : FONT_SMALL
//   Set indicator  : FONT_XTINY
//   Phase badge    : FONT_XTINY
//   Timer          : FONT_NUMBER_MEDIUM
//   Stats labels   : FONT_XTINY
//   Stats values   : FONT_XTINY
class DashboardView extends WatchUi.View {

    private var _engine as WorkoutEngine;
    private var _delegate as DashboardDelegate or Null;

    function initialize(engine as WorkoutEngine) {
        View.initialize();
        _engine = engine;
        _delegate = null;
    }

    // Wired by WorkoutSummaryDelegate after both view and delegate are constructed.
    // Used by onUpdate() to query the hold-to-exit progress ring.
    function setDelegate(d as DashboardDelegate) as Void {
        _delegate = d;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // No XML layout used. All drawing is done in onUpdate().
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var state   = _engine.getCurrentState();
        var workout = _engine.getWorkout();

        var screenW = dc.getWidth();
        var screenH = dc.getHeight();
        var centerX = screenW / 2;

        // Clear background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (state == null || workout == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, screenH / 2, Graphics.FONT_MEDIUM,
                        "GymPanion",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var phase = state.phase;

        // Phase dispatcher — no early returns so the hold overlay below
        // is drawn on top of every phase.
        if (phase == PHASE_FINISHED) {
            _drawFinishedScreen(dc, state, screenW, screenH, centerX);
        } else if (phase == PHASE_BLOCK_COMPLETE) {
            _drawBlockCompleteScreen(dc, state, workout, screenW, screenH, centerX);
        } else {
            var block = _engine.getCurrentBlock();
            if (block != null) {
                if (block.type == BLOCK_EMOM) {
                    _drawEmomDashboard(dc, state, block, screenW, screenH, centerX);
                } else if (block.type == BLOCK_AMRAP) {
                    _drawAmrapDashboard(dc, state, block, screenW, screenH, centerX);
                } else {
                    _drawSequentialDashboard(dc, state, screenW, screenH, centerX);
                }
            }
        }

        // Hold-to-exit overlay — drawn on top of every phase.
        if (_delegate != null) {
            var p = _delegate.getBackHoldProgress();
            if (p > 0.0) {
                _drawHoldOverlay(dc, screenW, screenH, centerX, p);
            }
        }
    }

    // ── Block Complete interstitial ─────────────────────────────────────
    private function _drawBlockCompleteScreen(dc as Graphics.Dc, state as SessionState,
                                               workout as Workout,
                                               screenW as Number, screenH as Number,
                                               centerX as Number) as Void {
        var hLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        var hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        var gap = 8;

        // "BLOCK DONE" title
        var totalH = hLarge + gap + hSmall + gap + hXtiny;
        var y = screenH / 2 - totalH / 2;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, Graphics.FONT_LARGE,
                    "BLOCK DONE", Graphics.TEXT_JUSTIFY_CENTER);
        y += hLarge + gap;

        // Next block name
        var blocks = workout.blocks;
        var nextIdx = state.currentBlockIndex;
        if (blocks != null && nextIdx < blocks.size()) {
            var nextBlock = blocks[nextIdx] as WorkoutBlock;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_SMALL,
                        "Next: " + nextBlock.name, Graphics.TEXT_JUSTIFY_CENTER);
        }
        y += hSmall + gap;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.blockCompleteHint) as String,
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ── Sequential dashboard (largely unchanged from original) ──────────
    private function _drawSequentialDashboard(dc as Graphics.Dc, state as SessionState,
                                               screenW as Number, screenH as Number,
                                               centerX as Number) as Void {
        var exerciseName = _engine.getCurrentExerciseName();
        var targetReps   = _engine.getCurrentTargetReps();
        var targetWeight = _engine.getCurrentTargetWeight();
        var totalSets    = _engine.getCurrentTotalSets();
        var setNum       = state.currentSetIndex + 1;

        var leftX  = screenW / 4;
        var rightX = (screenW * 3) / 4;

        var hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        var hTimer = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var GAP_SM = 4; var GAP_MD = 6; var GAP_LG = 8;

        var y = 44;
        var y_name = y;  y += hSmall + GAP_SM;
        var y_set = y;   y += hXtiny + GAP_SM;
        var y_badge = y; y += hXtiny + GAP_MD;
        var y_div1 = y;  y += 1 + GAP_LG;
        var y_timer = y; y += hTimer + GAP_LG;
        var y_div2 = y;  y += 1 + GAP_MD;
        var y_labels = y; y += hXtiny + 2;
        var y_values = y;

        // Exercise name
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_name, Graphics.FONT_SMALL,
                    exerciseName, Graphics.TEXT_JUSTIFY_CENTER);

        // Set indicator
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_set, Graphics.FONT_XTINY,
                    "Set " + setNum.toString() + " / " + totalSets.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Phase badge
        _drawPhaseBadge(dc, state.phase, centerX, y_badge);

        // Dividers
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div1, 205, y_div1);

        // Timer
        var timerText  = _formatTimer(state);
        var timerColor = _timerColor(state);
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_timer, Graphics.FONT_NUMBER_MEDIUM,
                    timerText, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div2, 205, y_div2);

        // Stats: REPS | HR | WEIGHT
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX,  y_labels, Graphics.FONT_XTINY, "REPS",   Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y_labels, Graphics.FONT_XTINY, "WEIGHT", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_labels, Graphics.FONT_XTINY, "HR",    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX,  y_values, Graphics.FONT_XTINY,
                    targetReps.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y_values, Graphics.FONT_XTINY,
                    targetWeight.format("%.1f") + " kg", Graphics.TEXT_JUSTIFY_CENTER);
        _drawHeartRate(dc, state, centerX, y_values);

        if (state.phase == PHASE_IDLE) {
            _drawBottomHint(dc, centerX, screenH,
                WatchUi.loadResource(Rez.Strings.idleStartHint) as String);
        }
    }

    // ── EMOM dashboard ──────────────────────────────────────────────────
    private function _drawEmomDashboard(dc as Graphics.Dc, state as SessionState,
                                         block as WorkoutBlock,
                                         screenW as Number, screenH as Number,
                                         centerX as Number) as Void {
        var exerciseName = _engine.getCurrentExerciseName();
        var targetReps   = _engine.getCurrentTargetReps();
        var totalRounds  = (block.rounds != null) ? block.rounds.size() : 0;
        var currentRound = state.currentRoundIndex + 1;

        var leftX  = screenW / 4;
        var rightX = (screenW * 3) / 4;

        var hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        var hTimer = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var GAP_SM = 4; var GAP_MD = 6; var GAP_LG = 8;

        var y = 44;
        var y_name = y;  y += hSmall + GAP_SM;
        var y_round = y; y += hXtiny + GAP_SM;
        var y_badge = y; y += hXtiny + GAP_MD;
        var y_div1 = y;  y += 1 + GAP_LG;
        var y_timer = y; y += hTimer + GAP_LG;
        var y_div2 = y;  y += 1 + GAP_MD;
        var y_labels = y; y += hXtiny + 2;
        var y_values = y;

        // Exercise name
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_name, Graphics.FONT_SMALL,
                    exerciseName, Graphics.TEXT_JUSTIFY_CENTER);

        // Round indicator
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_round, Graphics.FONT_XTINY,
                    "Round " + currentRound.toString() + " / " + totalRounds.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Phase badge
        _drawPhaseBadge(dc, state.phase, centerX, y_badge);

        // Divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div1, 205, y_div1);

        // Timer: interval countdown
        var timerText = _formatTimer(state);
        var timerColor = state.timerValueMs <= 5000 ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
        if (state.timerValueMs <= 0) { timerColor = Graphics.COLOR_RED; }
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_timer, Graphics.FONT_NUMBER_MEDIUM,
                    timerText, Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div2, 205, y_div2);

        // Stats: REPS | HR | TOTAL (remaining)
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX,  y_labels, Graphics.FONT_XTINY, "REPS",  Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y_labels, Graphics.FONT_XTINY, "TOTAL", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_labels, Graphics.FONT_XTINY, "HR",   Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, y_values, Graphics.FONT_XTINY,
                    targetReps.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        // Total remaining time
        var strategy = _engine.getStrategy();
        var totalRemSec = 0;
        if (strategy instanceof EmomStrategy) {
            totalRemSec = (strategy as EmomStrategy).getTotalRemainingSec(state, block);
        }
        var totalMin = totalRemSec / 60;
        var totalSecPart = totalRemSec % 60;
        var totalSecStr = totalSecPart < 10 ? "0" + totalSecPart.toString() : totalSecPart.toString();
        dc.drawText(rightX, y_values, Graphics.FONT_XTINY,
                    totalMin.toString() + ":" + totalSecStr, Graphics.TEXT_JUSTIFY_CENTER);

        _drawHeartRate(dc, state, centerX, y_values);

        if (state.phase == PHASE_IDLE) {
            _drawBottomHint(dc, centerX, screenH,
                WatchUi.loadResource(Rez.Strings.idleStartHint) as String);
        }
    }

    // ── AMRAP dashboard ─────────────────────────────────────────────────
    private function _drawAmrapDashboard(dc as Graphics.Dc, state as SessionState,
                                          block as WorkoutBlock,
                                          screenW as Number, screenH as Number,
                                          centerX as Number) as Void {
        var exerciseName = _engine.getCurrentExerciseName();
        var targetReps   = _engine.getCurrentTargetReps();

        var leftX  = screenW / 4;
        var rightX = (screenW * 3) / 4;

        var hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        var hTimer = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var GAP_SM = 4; var GAP_MD = 6; var GAP_LG = 8;

        var y = 44;
        var y_name = y;  y += hSmall + GAP_SM;
        var y_round = y; y += hXtiny + GAP_SM;
        var y_badge = y; y += hXtiny + GAP_MD;
        var y_div1 = y;  y += 1 + GAP_LG;
        var y_timer = y; y += hTimer + GAP_LG;
        var y_div2 = y;  y += 1 + GAP_MD;
        var y_labels = y; y += hXtiny + 2;
        var y_values = y;

        // Exercise name
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_name, Graphics.FONT_SMALL,
                    exerciseName, Graphics.TEXT_JUSTIFY_CENTER);

        // Round indicator
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_round, Graphics.FONT_XTINY,
                    "Round " + state.amrapRoundsCompleted.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Phase badge
        _drawPhaseBadge(dc, state.phase, centerX, y_badge);

        // Divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div1, 205, y_div1);

        // Timer: total countdown
        var timerText = _formatTimer(state);
        var timerColor = state.timerValueMs <= 10000 ? Graphics.COLOR_YELLOW : Graphics.COLOR_WHITE;
        if (state.timerValueMs <= 0) { timerColor = Graphics.COLOR_RED; }
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_timer, Graphics.FONT_NUMBER_MEDIUM,
                    timerText, Graphics.TEXT_JUSTIFY_CENTER);

        // Divider
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(55, y_div2, 205, y_div2);

        // Stats: REPS | HR
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX,  y_labels, Graphics.FONT_XTINY, "REPS",  Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_labels, Graphics.FONT_XTINY, "HR",   Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, y_values, Graphics.FONT_XTINY,
                    targetReps.toString(), Graphics.TEXT_JUSTIFY_CENTER);

        _drawHeartRate(dc, state, centerX, y_values);

        if (state.phase == PHASE_IDLE) {
            _drawBottomHint(dc, centerX, screenH,
                WatchUi.loadResource(Rez.Strings.idleStartHint) as String);
        }
    }

    // ── Shared helpers ──────────────────────────────────────────────────

    // Draws a small hint line near the bottom of the screen.
    // Used in IDLE ("Press START to begin") and BLOCK_COMPLETE paths.
    private function _drawBottomHint(dc as Graphics.Dc, centerX as Number,
                                      screenH as Number, hintText as String) as Void {
        var hXtiny = dc.getFontHeight(Graphics.FONT_XTINY);
        // Position 6 px above the bottom of the safe zone.
        var y = screenH - hXtiny - 6;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y, Graphics.FONT_XTINY, hintText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // When the user is holding BACK, overlay a progress arc + "Exit" label
    // centred on the screen. progress is 0.0..1.0; 1.0 = 3 s threshold reached.
    private function _drawHoldOverlay(dc as Graphics.Dc, screenW as Number,
                                       screenH as Number, centerX as Number,
                                       progress as Float) as Void {
        var centerY = screenH / 2;
        var radius = (screenW < screenH ? screenW : screenH) / 2 - 16;

        // Arc: draws from degreeStart to degreeEnd going clockwise when using
        // ARC_CLOCKWISE. 12 o'clock is 90°; sweep fills clockwise from there.
        var sweep = (360.0 * progress).toNumber();
        var degStart = 90;
        var degEnd = 90 - sweep;
        if (degEnd < degStart - 360) { degEnd = degStart - 360; }

        dc.setPenWidth(8);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(centerX, centerY, radius, Graphics.ARC_CLOCKWISE, degStart, degEnd);
        dc.setPenWidth(1);

        // Centred "Exit" label, medium font.
        var label = WatchUi.loadResource(Rez.Strings.backHoldExitLabel) as String;
        var hMed = dc.getFontHeight(Graphics.FONT_MEDIUM);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, centerY - hMed / 2, Graphics.FONT_MEDIUM,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _drawPhaseBadge(dc as Graphics.Dc, phase as Number,
                                      centerX as Number, y as Number) as Void {
        var phaseText  = "";
        var phaseColor = Graphics.COLOR_WHITE;
        if (phase == PHASE_WORK) {
            phaseText = "WORK"; phaseColor = Graphics.COLOR_GREEN;
        } else if (phase == PHASE_REST) {
            phaseText = "REST"; phaseColor = Graphics.COLOR_ORANGE;
        } else if (phase == PHASE_IDLE) {
            phaseText = "READY"; phaseColor = Graphics.COLOR_LT_GRAY;
        }
        if (phaseText.length() > 0) {
            dc.setColor(phaseColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, y, Graphics.FONT_XTINY,
                        phaseText, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Draws the workout-complete summary screen.
    // Both lines are vertically centred as a pair using runtime font heights.
    private function _drawFinishedScreen(dc as Graphics.Dc, state as SessionState,
                                          screenW as Number, screenH as Number,
                                          centerX as Number) as Void {
        var hLarge = dc.getFontHeight(Graphics.FONT_LARGE);
        var hSmall = dc.getFontHeight(Graphics.FONT_SMALL);
        var gap    = 8;
        var totalH = hLarge + gap + hSmall;
        var y_done = screenH / 2 - totalH / 2;
        var y_sets = y_done + hLarge + gap;

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_done, Graphics.FONT_LARGE,
                    "DONE", Graphics.TEXT_JUSTIFY_CENTER);

        var totalSets = state.completedSets.size().toString() + " sets";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, y_sets, Graphics.FONT_SMALL,
                    totalSets, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Formats the timer value for display as "M:SS" or "-M:SS" for overtime.
    // Returns "0:00" for PHASE_IDLE — the phase badge already shows "READY",
    // so repeating it in the timer zone is redundant.
    private function _formatTimer(state as SessionState) as String {
        var phase = state.phase;

        if (phase == PHASE_IDLE) {
            return "0:00";
        }

        var ms       = state.timerValueMs;
        var negative = false;

        if (ms < 0) {
            negative = true;
            ms = -ms;
        }

        var totalSec = ms / 1000;
        var minutes  = totalSec / 60;
        var seconds  = totalSec % 60;

        var secStr = seconds.toString();
        if (seconds < 10) {
            secStr = "0" + secStr;
        }
        var result = minutes.toString() + ":" + secStr;
        if (negative) {
            result = "-" + result;
        }
        return result;
    }

    // Returns the colour for the timer text based on phase and remaining time.
    private function _timerColor(state as SessionState) as Number {
        if (state.phase == PHASE_REST) {
            var ms = state.timerValueMs;
            if (ms <= 0) {
                return Graphics.COLOR_RED;
            }
            if (ms <= 10000) {
                return Graphics.COLOR_YELLOW;
            }
        }
        return Graphics.COLOR_WHITE;
    }

    // Draws the heart rate value at (x, y) in white FONT_XTINY, centered.
    // Draws only the BPM number (or "--"); the "HR" label is drawn inline in
    // the stats labels row above this call site.
    private function _drawHeartRate(dc as Graphics.Dc, state as SessionState,
                                     x as Number, y as Number) as Void {
        var hrText = "--";
        var sets   = state.completedSets;
        if (sets != null && sets.size() > 0) {
            var lastSet = sets[sets.size() - 1] as Dictionary;
            if (lastSet != null) {
                var hr = lastSet["hr"];
                if (hr != null && hr > 0) {
                    hrText = hr.toString();
                }
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY,
                    hrText, Graphics.TEXT_JUSTIFY_CENTER);
    }

}
