import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.Application;

//! Glance-loop tile: a red dot + "L308 Light" and the last-known pattern (saved to
//! Storage by the app). Selecting the glance launches the full controller. The glance
//! runs in its own lightweight context, so it does NOT hold a BLE connection — it just
//! shows the last state and acts as a one-flick launcher.
(:glance)
class L308GlanceView extends WatchUi.GlanceView {

    public function initialize() {
        GlanceView.initialize();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var h = dc.getHeight();
        var cy = h / 2;

        // Last-known pattern saved by the app (null until the app has connected once).
        var line2 = "Tap to control";
        var n = Application.Storage.getValue("count");
        var idx = Application.Storage.getValue("index");
        if (n != null && idx != null && (n as Number) > 0) {
            line2 = "Pattern " + ((idx as Number) + 1) + " / " + (n as Number);
        }

        // red taillight dot
        var r = h / 6;
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(r + 4, cy, r);

        var tx = r * 2 + 14;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, cy - h / 5, Graphics.FONT_TINY, "L308 Light",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx, cy + h / 5, Graphics.FONT_XTINY, line2,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
