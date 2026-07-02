import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Device-app entry point. Owns the BLE manager and wires up the view + input delegate.
class L308App extends Application.AppBase {

    private var _ble as L308BleManager?;

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
        // Creating the manager kicks off: register profile -> scan -> connect.
        _ble = new L308BleManager();
    }

    public function onStop(state as Dictionary?) as Void {
        if (_ble != null) {
            _ble.close();
            _ble = null;
        }
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [ new L308View(_ble), new L308Delegate(_ble) ];
    }

    // Glance-loop tile (one flick from the watch face); selecting it launches the app.
    // (:glance)-scoped so the glance process loads only the tile, not the BLE engine.
    (:glance)
    public function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [ new L308GlanceView() ];
    }
}
