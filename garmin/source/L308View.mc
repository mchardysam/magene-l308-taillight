import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;

//! Status screen: a coloured connection dot + label, a hero pattern number, "of N",
//! prev/next chevrons, and a row of position dots. Grey when disconnected, blue/active
//! when connected (mirrors the C606). Laid out to stay inside a round screen's safe area.
class L308View extends WatchUi.View {

    private var _ble as L308BleManager?;

    public function initialize(ble as L308BleManager?) {
        View.initialize();
        _ble = ble;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        var ble = _ble;
        var ready = (ble != null) && ble.isReady();
        var accent = ready ? Graphics.COLOR_BLUE : Graphics.COLOR_DK_GRAY;
        var primary = ready ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- status pill: coloured dot + label, centred in the upper third ---
        var statusText = (ble != null) ? ble.statusText : "Starting...";
        var dotR = 6;
        var gap = 8;
        var tw = dc.getTextWidthInPixels(statusText, Graphics.FONT_TINY);
        var groupW = dotR * 2 + gap + tw;
        var gx = (cx - groupW / 2).toNumber();
        var sy = (cy - h * 26 / 100).toNumber();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx + dotR, sy, dotR);
        dc.setColor(primary, Graphics.COLOR_TRANSPARENT);
        dc.drawText(gx + dotR * 2 + gap, sy, Graphics.FONT_TINY, statusText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        if (ble != null && ble.patternCount > 0) {
            var idx = ble.currentIndex;
            var n = ble.patternCount;

            // hero number (slightly above true centre to leave room for "of N")
            dc.setColor(primary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 8, Graphics.FONT_NUMBER_HOT, (idx + 1).toString(), center);

            // "of N" (extra gap below the hero number)
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (cy + h * 19 / 100).toNumber(), Graphics.FONT_TINY,
                "of " + n.toString(), center);

            // prev/next chevrons at the sides, vertically centred
            var chH = 16;
            var chW = 12;
            var pad = (w * 12 / 100).toNumber();
            dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[pad + chW, cy - chH], [pad, cy], [pad + chW, cy + chH]]);
            dc.fillPolygon([[w - pad - chW, cy - chH], [w - pad, cy], [w - pad - chW, cy + chH]]);

            // position dots (only when they comfortably fit)
            if (n <= 12) {
                var dgap = 14;
                var rowW = (n - 1) * dgap;
                var dx0 = (cx - rowW / 2).toNumber();
                var dy = (cy + h * 28 / 100).toNumber();
                for (var i = 0; i < n; i += 1) {
                    if (i == idx) {
                        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
                        dc.fillCircle(dx0 + i * dgap, dy, 4);
                    } else {
                        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                        dc.fillCircle(dx0 + i * dgap, dy, 3);
                    }
                }
            }
        } else {
            dc.setColor(primary, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_SMALL, "L308 Light", center);
        }
    }
}
