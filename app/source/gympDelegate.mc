import Toybox.Lang;
import Toybox.WatchUi;

class gympDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new gympMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}