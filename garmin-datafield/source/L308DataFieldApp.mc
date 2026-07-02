import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

//! Data-field app entry. getInitialView returns the data field shown on a ride data screen.
class L308DataFieldApp extends Application.AppBase {

    private var _field as L308DataField?;

    public function initialize() {
        AppBase.initialize();
    }

    // Non-touch devices: display-only (no input delegate).
    (:nonTouchScreen)
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var f = new L308DataField();
        _field = f;
        return [ f ];
    }

    // Touch devices: return a tap delegate too, so the field gets in-ride taps.
    (:touchScreen)
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var f = new L308DataField();
        _field = f;
        return [ f, new L308FieldDelegate(f) ];
    }

    // Re-read settings when the user changes them in Garmin Connect.
    public function onSettingsChanged() as Void {
        if (_field != null) {
            _field.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
