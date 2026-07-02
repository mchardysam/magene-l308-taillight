import Toybox.WatchUi;
import Toybox.Lang;

//! Input: maps prev/next to physical keys (UP/DOWN), page behaviors, and touch swipes.
//! "left/right" == prev/next: UP / page-prev / swipe-left = previous,
//! DOWN / page-next / swipe-right = next.
class L308Delegate extends WatchUi.BehaviorDelegate {

    private var _ble as L308BleManager?;

    public function initialize(ble as L308BleManager?) {
        BehaviorDelegate.initialize();
        _ble = ble;
    }

    public function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            prev();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            next();
            return true;
        }
        return false;
    }

    // Page behaviors map to prev/next on devices without UP/DOWN keys.
    public function onPreviousPage() as Boolean {
        prev();
        return true;
    }

    public function onNextPage() as Boolean {
        next();
        return true;
    }

    // MENU = resync from the light (re-query current pattern + count).
    public function onMenu() as Boolean {
        if (_ble != null) { _ble.refresh(); }
        return true;
    }

    // Touch devices: swipe left = prev, swipe right = next.
    public function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var dir = evt.getDirection();
        if (dir == WatchUi.SWIPE_LEFT) {
            prev();
            return true;
        } else if (dir == WatchUi.SWIPE_RIGHT) {
            next();
            return true;
        }
        return false;
    }

    private function prev() as Void {
        if (_ble != null) { _ble.prev(); }
    }

    private function next() as Void {
        if (_ble != null) { _ble.next(); }
    }
}
