import Toybox.Graphics;
import Toybox.Lang;

// TextHelper: single-function module that returns a possibly-ellipsized string
// guaranteed to fit within `maxWidth` pixels when drawn at the given font.
//
// Used by the dashboard screens to prevent dynamic workout data (exercise
// names, block names) from overflowing the display on the Forerunner 265.
// Font-shrinking is intentionally avoided because DashboardView's y-cursor
// layout accumulates font heights — changing the font would cascade through
// layout math. Ellipsis is the safer, reusable strategy.
//
// Complexity: O(log n) calls to getTextWidthInPixels via binary search over
// prefix length, where n = text.length().
module TextHelper {

    // Returns the input text if it fits within maxWidth at the given font;
    // otherwise returns the longest prefix that fits with "…" appended.
    // Returns "" if even "…" alone cannot fit.
    function fitText(dc as Graphics.Dc, text as String, maxWidth as Number,
                     font as Graphics.FontType) as String {
        if (text == null || text.length() == 0) { return ""; }
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }

        var ellipsis = "…";
        var ellipsisW = dc.getTextWidthInPixels(ellipsis, font);
        if (ellipsisW > maxWidth) { return ""; }

        // Binary search for the longest prefix length n such that
        // width(text.substring(0, n) + "…") <= maxWidth.
        var lo = 0;
        var hi = text.length();
        var best = 0;
        while (lo <= hi) {
            var mid = (lo + hi) / 2;
            var candidate = text.substring(0, mid) + ellipsis;
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                best = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return text.substring(0, best) + ellipsis;
    }
}
