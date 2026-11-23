import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;

class HorizonteApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        var v = new HorizonteView();
        return [v, new HorizonteDelegate(v)];
    }
}

// Botones: START o mantener UP -> ajustes. UP/DOWN giran la vista si no hay brújula (simulador).
class HorizonteDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(v) {
        BehaviorDelegate.initialize();
        view = v;
    }

    function onSelect() {
        openMenu();
        return true;
    }

    function onMenu() {
        openMenu();
        return true;
    }

    function onPreviousPage() {
        view.manualHead = Geo.norm360(view.manualHead - 10.0);
        return true;
    }

    function onNextPage() {
        view.manualHead = Geo.norm360(view.manualHead + 10.0);
        return true;
    }

    function openMenu() {
        var m = new WatchUi.Menu2({:title => "Horizonte"});
        m.addItem(new WatchUi.ToggleMenuItem("Tema oscuro", null, :dark, view.dark, null));
        m.addItem(new WatchUi.ToggleMenuItem("Sol", null, :sun, view.showSun, null));
        m.addItem(new WatchUi.ToggleMenuItem("Invertir inclinación", null, :inv, view.invPitch, null));
        m.addItem(new WatchUi.MenuItem("Tamaño zona", view.areaKm.toString() + " x " + view.areaKm.toString() + " km", :size, null));
        m.addItem(new WatchUi.MenuItem("Descargar zona aquí", view.store.areaCount().toString() + " teselas guardadas", :dl, null));
        m.addItem(new WatchUi.MenuItem("Borrar zonas y caché", null, :clr, null));
        m.addItem(new WatchUi.MenuItem("Recalcular", null, :re, null));
        WatchUi.pushView(m, new HorizonteMenuDelegate(view), WatchUi.SLIDE_UP);
    }
}

class HorizonteMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view;

    function initialize(v) {
        Menu2InputDelegate.initialize();
        view = v;
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :dark) {
            view.dark = item.isEnabled();
            view.saveSettings();
        } else if (id == :sun) {
            view.showSun = item.isEnabled();
            view.saveSettings();
        } else if (id == :inv) {
            view.invPitch = item.isEnabled();
            view.saveSettings();
        } else if (id == :size) {
            if (view.areaKm == 10) { view.areaKm = 20; }
            else if (view.areaKm == 20) { view.areaKm = 30; }
            else if (view.areaKm == 30) { view.areaKm = 50; }
            else { view.areaKm = 10; }
            view.saveSettings();
            item.setSubLabel(view.areaKm.toString() + " x " + view.areaKm.toString() + " km");
            WatchUi.requestUpdate();
        } else if (id == :dl) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            view.startArea();
        } else if (id == :clr) {
            view.store.clearAll();
            item.setSubLabel("Hecho");
            WatchUi.requestUpdate();
        } else if (id == :re) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            view.forceRecalc();
        }
    }
}
