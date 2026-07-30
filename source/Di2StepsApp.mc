import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// di2steps — reads Shimano STEPS (SC-EM800) shifting/assist data over BLE and
// renders it as a Connect IQ data field. Sibling to GearRatio, which reads the
// same class of data over ANT+ Di2; this app is for bikes where the Di2 stream
// is not exposed but the STEPS BLE stream is. See the project plan and
// docs/SCEM800-BLE-protocol.md for the wire format.
class Di2StepsApp extends Application.AppBase {

    private var _view as Di2StepsView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new Di2StepsView();
        _view.setupBle();
        return [_view];
    }

    // Stage 4 returns the on-device tooth-count wizard here.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return null;
    }

    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.onSettingsChanged();
        }
    }
}
