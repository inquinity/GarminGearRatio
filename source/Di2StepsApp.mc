import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// di2steps — shows drivetrain gear positions and the resulting gear ratio as a
// Connect IQ data field, for a Shimano STEPS (SC-EM800) bike.
//
// Gear positions come from Toybox.Activity.Info, which the head unit populates
// from its own STEPS pairing; tooth counts come from app settings. The app
// needs no permissions at all. Sibling to GearRatio (../GarminGearRatio), which
// solves the same problem from a raw ANT+ Di2 channel.
class Di2StepsApp extends Application.AppBase {

    private var _view as Di2StepsView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new Di2StepsView();
        return [_view];
    }

    // On-device tooth-count wizard, reachable from the field's settings.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return [new GearSettingsView(), new GearSettingsDelegate()];
    }

    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.onSettingsChanged();
        }
    }
}
