import Toybox.Lang;
import Toybox.Application;
import Toybox.Activity;
import Toybox.Time;
import Toybox.System;

//! Evaluates the rule hierarchy and returns the target pattern slot (0-based), or -1 for
//! "do nothing" (Manual mode). Reads config from Application.Properties. Includes band
//! hysteresis and a global min-dwell debounce (battery bypasses dwell).
class RulesEngine {

    enum { MODE_AUTO, MODE_MANUAL, MODE_GROUP }

    public var mode as Number = MODE_AUTO;

    private var _default as Number = 0;
    private var _groupSlot as Number = 0;
    private var _speedEnabled as Boolean = true;
    private var _speedThresh as Number = 40;
    private var _speedSlot as Number = 1;
    private var _powerEnabled as Boolean = false;
    private var _powerThresh as Number = 250;
    private var _powerSlot as Number = 1;
    private var _cadenceEnabled as Boolean = false;
    private var _cadenceThresh as Number = 90;
    private var _cadenceSlot as Number = 1;
    private var _batteryEnabled as Boolean = false;
    private var _batteryPct as Number = 15;
    private var _batterySlot as Number = 0;
    private var _hysteresis as Number = 3;
    private var _minDwellMs as Number = 8000;

    private var _speedHigh as Boolean = false;
    private var _powerHigh as Boolean = false;
    private var _cadenceHigh as Boolean = false;
    private var _committed as Number = 0;
    private var _lastSwitchMs as Number = 0;
    private var _rule as String = "DEFAULT";   // which rule last fired (for display)

    public function initialize() {
        loadSettings();
    }

    public function isManual() as Boolean { return mode == MODE_MANUAL; }
    public function isGroup() as Boolean { return mode == MODE_GROUP; }

    public function defaultSlot() as Number { return _default; }

    // Which rule produced the current pattern: DEFAULT/SPEED/POWER/CADENCE/BATT, or STEADY in group.
    public function activeRule() as String { return _rule; }

    public function modeLabel() as String {
        if (mode == MODE_MANUAL) { return "MANUAL"; }
        if (mode == MODE_GROUP) { return "GROUP"; }
        return "AUTO";
    }

    // Tap on touch devices cycles Auto -> Manual -> Group; persist so it sticks.
    public function cycleMode() as Void {
        mode = (mode + 1) % 3;
        Application.Properties.setValue("mode", mode);
    }

    public function setManual() as Void {
        mode = MODE_MANUAL;
        Application.Properties.setValue("mode", mode);
    }

    public function loadSettings() as Void {
        mode = numProp("mode", 0);
        _default = numProp("defaultPattern", 1) - 1;
        _groupSlot = numProp("groupPattern", 1) - 1;
        _speedEnabled = boolProp("speedEnabled", true);
        _speedThresh = numProp("speedThreshold", 40);
        _speedSlot = numProp("speedPattern", 2) - 1;
        _powerEnabled = boolProp("powerEnabled", false);
        _powerThresh = numProp("powerThreshold", 250);
        _powerSlot = numProp("powerPattern", 2) - 1;
        _cadenceEnabled = boolProp("cadenceEnabled", false);
        _cadenceThresh = numProp("cadenceThreshold", 90);
        _cadenceSlot = numProp("cadencePattern", 2) - 1;
        _batteryEnabled = boolProp("batteryEnabled", false);
        _batteryPct = numProp("batteryPct", 15);
        _batterySlot = numProp("batteryPattern", 1) - 1;
        _hysteresis = numProp("hysteresis", 3);
        _minDwellMs = numProp("minDwellSec", 8) * 1000;
        _committed = _default;
    }

    private function numProp(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key) as Number?;
        if (v == null) { return dflt; }
        return v;
    }

    private function boolProp(key as String, dflt as Boolean) as Boolean {
        var v = Application.Properties.getValue(key) as Boolean?;
        if (v == null) { return dflt; }
        return v;
    }

    //! Returns the target slot (0-based), or -1 for do-nothing.
    //! battLevel: 0-100, or -1 unknown.
    public function evaluate(info as Activity.Info, battLevel as Number) as Number {
        if (mode == MODE_MANUAL) { return -1; }

        var raw;
        var bypassDwell = false;

        if (mode == MODE_GROUP) {
            // Courtesy steady pattern so you're not flashing the rider on your wheel.
            raw = _groupSlot; _rule = "STEADY";
        } else { // AUTO hierarchy, highest priority first
            if (_batteryEnabled && battLevel >= 0 && battLevel <= _batteryPct) {
                raw = _batterySlot; bypassDwell = true; _rule = "BATT";
            } else if (_speedEnabled && speedAbove(info)) {
                raw = _speedSlot; _rule = "SPEED";
            } else if (_powerEnabled && powerAbove(info)) {
                raw = _powerSlot; _rule = "POWER";
            } else if (_cadenceEnabled && cadenceAbove(info)) {
                raw = _cadenceSlot; _rule = "CADENCE";
            } else {
                raw = _default; _rule = "DEFAULT";
            }
        }

        var now = System.getTimer();
        if (raw != _committed) {
            if (bypassDwell || (now - _lastSwitchMs) >= _minDwellMs) {
                _committed = raw;
                _lastSwitchMs = now;
            }
        }
        return _committed;
    }

    // Speed band with hysteresis (up at threshold, down at threshold - deadband).
    private function speedAbove(info as Activity.Info) as Boolean {
        var sp = info.currentSpeed;
        if (sp == null) { return _speedHigh; }
        var kmh = sp * 3.6;
        if (kmh >= _speedThresh) { _speedHigh = true; }
        else if (kmh <= _speedThresh - _hysteresis) { _speedHigh = false; }
        return _speedHigh;
    }

    // Power band with a small deadband (Watts).
    private function powerAbove(info as Activity.Info) as Boolean {
        var p = info.currentPower;
        if (p == null) { return _powerHigh; }
        if (p >= _powerThresh) { _powerHigh = true; }
        else if (p <= _powerThresh - 15) { _powerHigh = false; }
        return _powerHigh;
    }

    // Cadence band with a small deadband (rpm).
    private function cadenceAbove(info as Activity.Info) as Boolean {
        var c = info.currentCadence;
        if (c == null) { return _cadenceHigh; }
        if (c >= _cadenceThresh) { _cadenceHigh = true; }
        else if (c <= _cadenceThresh - 3) { _cadenceHigh = false; }
        return _cadenceHigh;
    }
}
