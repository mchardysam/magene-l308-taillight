import Toybox.Lang;
import Toybox.WatchUi;

//! Touch-only input for the data field. On touch-screen devices the app returns this
//! alongside the field from getInitialView(), so taps during the ride reach the field:
//!   left third = previous pattern, right third = next, centre = cycle Auto/Manual/Group.
//! Held as a weak reference to avoid a retain cycle (the field tends to outlive the delegate).
(:touchScreen)
class L308FieldDelegate extends WatchUi.InputDelegate {

    private var _field as Lang.WeakReference;

    public function initialize(field as L308DataField) {
        InputDelegate.initialize();
        _field = field.weak();
    }

    public function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_field.stillAlive()) {
            return (_field.get() as L308DataField).onTap(evt.getCoordinates());
        }
        return false;
    }
}
