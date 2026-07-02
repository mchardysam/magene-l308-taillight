import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.System;

//! The data field: each compute() reads ride data, evaluates the rule hierarchy,
//! and tells the BLE link which pattern to show (write-on-change only). onUpdate() draws a
//! compact status (mode + pattern). On touch devices (via L308FieldDelegate) taps give
//! in-ride control: left=prev, right=next, centre=cycle Auto/Manual/Group.
class L308DataField extends WatchUi.DataField {

    private var _link as BleLink;
    private var _engine as RulesEngine;
    private var _patternText as String = "--";
    private var _manualSlot as Number = 0;     // 0-based; the tap-controlled pattern
    private var _manualActive as Boolean = false;  // true once the rider taps prev/next
    private var _w as Number = 0;
    private var _h as Number = 0;

    public function initialize() {
        DataField.initialize();
        _link = new BleLink();
        _engine = new RulesEngine();
        _manualSlot = _engine.defaultSlot();
    }

    public function reloadSettings() as Void {
        _engine.loadSettings();
    }

    public function compute(info as Activity.Info) as Void {
        _link.ensureStarted();
        forcePreview();
        if (!_link.isReady()) { return; }
        var slot = -1;
        if (_engine.isManual()) {
            // Manual = hands-off until the rider taps prev/next, then hold that pick.
            if (_manualActive) { slot = _manualSlot; }
        } else {
            slot = _engine.evaluate(info, _link.battLevel);
        }
        if (slot >= 0) {
            _link.selectSlot(slot);
            _patternText = "P" + (slot + 1).toString();
        }
    }

    // Debug/simulator only: fake a connected light so the connected layout can be previewed
    // and screenshotted in the sim. The (:debug)/(:release) pair excludes it from store builds.
    (:debug) private function forcePreview() as Void { _link.previewConnected(8, 72); }
    (:release) private function forcePreview() as Void { }

    // Called by the touch delegate (touch devices only). coords = [x, y].
    public function onTap(coords as Lang.Array<Lang.Number>) as Boolean {
        if (_w <= 0) { return false; }
        if (!_engine.isManual()) {
            // No prev/next outside Manual (rules drive it) — any tap cycles the mode.
            _engine.cycleMode();
        } else {
            var x = coords[0];
            if (x < _w / 3) { manualStep(-1); }
            else if (x > _w * 2 / 3) { manualStep(1); }
            else { _engine.cycleMode(); }
        }
        WatchUi.requestUpdate();
        return true;
    }

    // Top-line context: Auto shows the firing rule; Group/Manual show the mode.
    private function topLabel() as String {
        if (_engine.isManual()) { return "MANUAL"; }
        if (_engine.isGroup()) { return "GROUP"; }
        return _engine.activeRule();   // DEFAULT / SPEED / POWER / CADENCE / BATT
    }

    // Corner mode glyph so the mode is unambiguous even when Auto shows a rule name.
    private function modeLetter() as String {
        if (_engine.isManual()) { return "M"; }
        if (_engine.isGroup()) { return "G"; }
        return "A";
    }

    private function modeColor() as Graphics.ColorType {
        if (_engine.isManual()) { return Graphics.COLOR_BLUE; }
        if (_engine.isGroup()) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_GREEN;
    }

    private function manualStep(delta as Number) as Void {
        var n = _link.patternCount;
        if (n <= 0) { return; }
        _engine.setManual();
        _manualActive = true;
        _manualSlot = ((_manualSlot + delta) % n + n) % n;
        _link.selectSlot(_manualSlot);
        _patternText = "P" + (_manualSlot + 1).toString();
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(fg, bg);
        dc.clear();

        // Keep content off any edge that's against the screen bezel (round screens / edge cells).
        // No border is drawn — the system already draws the data-screen grid.
        var f = getObscurityFlags();
        var top = ((f & DataField.OBSCURE_TOP) != 0) ? _h * 12 / 100 : 4;
        var bot = ((f & DataField.OBSCURE_BOTTOM) != 0) ? _h * 12 / 100 : 4;
        var usableH = _h - top - bot;
        var cx = _w / 2;

        var label;
        if (_engine.isManual() && !_manualActive) {
            label = "off";
        } else if (!_link.isReady()) {
            label = "...";
        } else {
            label = _patternText;
        }

        // Corner markers (mode letter, battery %). On round screens the true corners fall
        // outside the visible circle, so pull them in and down to stay on-glass.
        var round = (System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_RECTANGLE);
        var markY = round ? _h * 16 / 100 : top;
        var markL = round ? _w * 20 / 100 : (((f & DataField.OBSCURE_LEFT) != 0) ? _w * 12 / 100 : 4) + 2;
        var markR = round ? _w * 80 / 100 : _w - (((f & DataField.OBSCURE_RIGHT) != 0) ? _w * 12 / 100 : 4) - 2;

        // Mode letter (A/M/G), colour-coded.
        dc.setColor(modeColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(markL, markY, Graphics.FONT_XTINY, modeLetter(), Graphics.TEXT_JUSTIFY_LEFT);

        // Light battery % (top-right when known) — its presence also signals a live link.
        if (_link.battLevel >= 0) {
            var bcol = (_link.battLevel <= 15) ? Graphics.COLOR_RED
                     : ((_link.battLevel <= 40) ? Graphics.COLOR_ORANGE : fg);
            dc.setColor(bcol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(markR, markY, Graphics.FONT_XTINY,
                _link.battLevel.toString() + "%", Graphics.TEXT_JUSTIFY_RIGHT);
        }

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, top + usableH * 28 / 100, Graphics.FONT_XTINY, topLabel(), center);
        dc.drawText(cx, top + usableH * 66 / 100, Graphics.FONT_MEDIUM, label, center);

        drawTouchHints(dc, top + usableH / 2);
    }

    // Subtle left/right chevrons hinting the prev/next tap zones. Touch devices only;
    // non-touch builds get the empty version so no misleading arrows appear.
    (:touchScreen)
    private function drawTouchHints(dc as Graphics.Dc, cy as Number) as Void {
        if (!_engine.isManual()) { return; }   // prev/next arrows only apply in Manual mode
        var f = getObscurityFlags();
        var lInset = ((f & DataField.OBSCURE_LEFT) != 0) ? _w * 12 / 100 : 6;
        var rInset = ((f & DataField.OBSCURE_RIGHT) != 0) ? _w * 12 / 100 : 6;
        var cw = 7;
        var chh = 10;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var lx = lInset + cw;
        dc.fillPolygon([[lx + cw, cy - chh], [lx, cy], [lx + cw, cy + chh]]);
        var rx = _w - rInset - cw;
        dc.fillPolygon([[rx - cw, cy - chh], [rx, cy], [rx - cw, cy + chh]]);
    }

    (:nonTouchScreen)
    private function drawTouchHints(dc as Graphics.Dc, cy as Number) as Void {
    }
}
