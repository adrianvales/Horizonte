import Toybox.Lang;
import Toybox.Math;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.Time;
import Toybox.Application;

class HorizonteView extends WatchUi.View {
    var store;
    var pano;
    var timer;

    var heading = 0.0;
    var pitch = 0.0;
    var hasCompass = false;
    var manualHead = 0.0;

    var lat = null;
    var lon = null;
    var alt = null;
    var compLat = null;
    var compLon = null;
    var waitingTiles = false;
    var areaRunning = false;
    var msg = null;
    var msgUntil = 0;
    var sunNow = null;
    var tick = 0;

    // ajustes
    var dark = false;
    var showSun = true;
    var invPitch = false;
    var areaKm = 20;

    const C_GREEN = 0x00AA00;
    const C_MAGENTA = 0xAA00FF;
    const C_TEAL = 0x00AAAA;
    const C_SUN = 0xFFAA00;
    const CARD8 = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

    function initialize() {
        View.initialize();
        store = new TerrainStore(self);
        pano = new Panorama(store);
        timer = new Timer.Timer();
        loadSettings();
    }

    function loadSettings() {
        var v = Application.Storage.getValue("dark");
        if (v != null) { dark = v; }
        v = Application.Storage.getValue("sun");
        if (v != null) { showSun = v; }
        v = Application.Storage.getValue("inv");
        if (v != null) { invPitch = v; }
        v = Application.Storage.getValue("area");
        if (v != null) { areaKm = v; }
    }

    function saveSettings() {
        try {
            Application.Storage.setValue("dark", dark);
            Application.Storage.setValue("sun", showSun);
            Application.Storage.setValue("inv", invPitch);
            Application.Storage.setValue("area", areaKm);
        } catch (e) {
        }
    }

    function onShow() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPos));
        Sensor.enableSensorEvents(method(:onSensor));
        timer.start(method(:onTick), 100, true);
    }

    function onHide() {
        timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPos));
        Sensor.enableSensorEvents(null);
    }

    function onSensor(info) {
        // solo para mantener los sensores activos; se leen en onTick
    }

    function onPos(info) {
        if (info == null || info.position == null) { return; }
        if (info.accuracy != null && info.accuracy < Position.QUALITY_POOR) { return; }
        var dd = info.position.toDegrees();
        lat = dd[0].toFloat();
        lon = dd[1].toFloat();
        alt = info.altitude;
        if (compLat == null || distM(lat, lon, compLat, compLon) > Cfg.RECALC_DIST) {
            requestTerrain();
        }
    }

    function distM(a1, o1, a2, o2) {
        var dn = (a1 - a2) * 111320.0;
        var de = (o1 - o2) * 111320.0 * Math.cos(a1 * Geo.D2R);
        return Math.sqrt(dn * dn + de * de);
    }

    function requestTerrain() {
        if (lat == null || store.isRunning() || pano.computing()) { return; }
        compLat = lat;
        compLon = lon;
        waitingTiles = true;
        store.ensure(lat, lon);
    }

    function forceRecalc() {
        compLat = null;
        requestTerrain();
    }

    function startArea() {
        if (lat == null) {
            showMsg("Sin GPS todavía");
            return;
        }
        if (store.isRunning()) {
            showMsg("Espera, descargando…");
            return;
        }
        areaRunning = true;
        store.downloadArea(lat, lon, areaKm);
    }

    function showMsg(s) {
        msg = s;
        msgUntil = tick + 40;
    }

    // ---- avisos de TerrainStore ----
    function onStoreProgress() {
        WatchUi.requestUpdate();
    }

    function onTilesReady() {
        waitingTiles = false;
        var dem = store.elevAt(1, compLat, compLon);
        var h = dem + Cfg.EYE;
        if (alt != null && alt > h && alt < dem + 100.0) { h = alt; }
        pano.start(compLat, compLon, h);
        if (store.failed > 0) { showMsg("Sin conexión: faltan " + store.failed); }
    }

    function onAreaDone() {
        areaRunning = false;
        if (store.areaFull) {
            showMsg("Memoria llena (" + store.areaCount() + " guardadas)");
        } else if (store.failed > 0) {
            showMsg("Zona incompleta: faltan " + store.failed);
        } else {
            showMsg("Zona guardada");
        }
        compLat = null;   // recargar desde lo guardado
        requestTerrain();
    }

    // ---- bucle principal ----
    function onTick() {
        tick++;
        var info = Sensor.getInfo();
        if (info has :heading && info.heading != null) {
            hasCompass = true;
            var hd = Geo.norm360(info.heading * Geo.R2D);
            heading = Geo.norm360(heading + 0.35 * Geo.wrap180(hd - heading));
        } else {
            hasCompass = false;
            heading = heading + 0.35 * Geo.wrap180(manualHead - heading);
        }
        if (info has :accel && info.accel != null) {
            var ax = info.accel[0];
            var ay = info.accel[1];
            var az = info.accel[2];
            var p = Math.atan2(ay, Math.sqrt(ax * ax + az * az)) * Geo.R2D;
            if (invPitch) { p = -p; }
            pitch = pitch + 0.25 * (p - pitch);
        }
        if (pano.computing()) {
            pano.step(showSun);
        } else if (lat != null && compLat != null && !store.isRunning()
                   && distM(lat, lon, compLat, compLon) > Cfg.RECALC_DIST) {
            requestTerrain();
        }
        if (showSun && lat != null && (sunNow == null || tick % 100 == 0)) {
            sunNow = Sun.pos(Time.now().value(), lat, lon);
        }
        WatchUi.requestUpdate();
    }

    // ---- dibujo ----
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var bg = dark ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        var fg = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();

        if (!pano.ready) {
            drawStatus(dc, w, h, fg);
            return;
        }

        var pph = w / Cfg.HFOV;
        var ppv = pph * Cfg.VSCALE;
        var H = heading;
        var P = pitch;
        var half = Cfg.HFOV / 2.0 + 2.0;
        var r0 = Math.floor(H - half).toNumber();
        var r1 = Math.ceil(H + half).toNumber();
        var M = Cfg.MAXR;

        // relleno bajo el horizonte (tema oscuro) y horizonte
        var px = null;
        var py = null;
        dc.setPenWidth(2);
        for (var rr = r0; rr <= r1; rr++) {
            var ri = ((rr % 360) + 360) % 360;
            var n = pano.cnt[ri];
            var a = (n > 0) ? pano.ang[ri * M + n - 1] : 0.0;
            var x = (cx + (rr - H) * pph).toNumber();
            var y = clampY(cy - (a - P) * ppv, h);
            if (px != null) {
                if (dark) {
                    dc.setColor(C_TEAL, C_TEAL);
                    dc.fillPolygon([[px, py], [x, y], [x, h], [px, h]]);
                }
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }

        // crestas
        dc.setPenWidth(1);
        dc.setColor(dark ? Graphics.COLOR_BLACK : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var rr = r0; rr < r1; rr++) {
            var ri = ((rr % 360) + 360) % 360;
            var ri2 = (ri + 1) % 360;
            var n1 = pano.cnt[ri];
            var n2 = pano.cnt[ri2];
            var x1 = (cx + (rr - H) * pph).toNumber();
            var x2 = (cx + (rr + 1 - H) * pph).toNumber();
            for (var k = 0; k < n1 - 1; k++) {
                var j = pano.link[ri * M + k];
                if (j != null && j >= 0 && j < n2 - 1) {
                    dc.drawLine(x1, clampY(cy - (pano.ang[ri * M + k] - P) * ppv, h),
                                x2, clampY(cy - (pano.ang[ri2 * M + j] - P) * ppv, h));
                }
            }
        }

        // escala de elevación
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        for (var e = -20; e <= 30; e += 10) {
            var y = cy - (e - P) * ppv;
            if (y > h * 0.2 && y < h * 0.6) {
                var lbl = (e > 0) ? ("+" + e) : e.toString();
                dc.drawText(w * 0.2, y, Graphics.FONT_XTINY, lbl,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // brújula arriba
        var ty = h * 0.13;
        var a0 = (Math.ceil((H - Cfg.HFOV / 2.0) / 15.0)).toNumber() * 15;
        for (var a = a0; a <= H + Cfg.HFOV / 2.0; a += 15) {
            var x = cx + (a - H) * pph;
            var an = ((a % 360) + 360) % 360;
            if (an % 45 == 0) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, ty, Graphics.FONT_XTINY, CARD8[an / 45],
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, ty, Graphics.FONT_XTINY, an.toString(),
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x, ty + 10], [x - 3, ty + 15], [x + 3, ty + 15]]);
        }

        // cumbres
        var best = null;
        var bestS = 999.0;
        var bx = 0;
        var by = 0;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var vis = pano.vis;
        for (var i = 0; i < vis.size(); i++) {
            var p = vis[i];
            var dA = Geo.wrap180(p[1] - H);
            if (dA.abs() > half) { continue; }
            var x = cx + dA * pph;
            var y = cy - (p[2] - P) * ppv;
            dc.fillPolygon([[x, y - 5], [x - 4, y + 1], [x + 4, y + 1]]);
            if (dA.abs() < Cfg.TARGET_DEG) {
                var s = dA.abs() + 0.3 * (p[2] - P).abs();
                if (s < bestS) {
                    bestS = s;
                    best = p;
                    bx = x;
                    by = y;
                }
            }
        }

        // sol
        var sunTarget = false;
        if (showSun && sunNow != null) {
            var dA = Geo.wrap180(sunNow[0] - H);
            if (dA.abs() < half) {
                var x = cx + dA * pph;
                var y = cy - (sunNow[1] - P) * ppv;
                dc.setColor(C_SUN, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, 6);
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, 6);
                if (best == null && dA.abs() < Cfg.TARGET_DEG) { sunTarget = true; }
            }
        }

        // mira
        dc.setColor(C_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(cx, cy, 7);
        dc.drawLine(cx - 12, cy, cx - 4, cy);
        dc.drawLine(cx + 4, cy, cx + 12, cy);
        dc.drawLine(cx, cy - 12, cx, cy - 4);
        dc.drawLine(cx, cy + 4, cx, cy + 12);
        dc.setPenWidth(1);
        var td = terrainDist(H, P);
        if (td != null) {
            dc.drawText(cx + 12, cy - 14, Graphics.FONT_XTINY, Geo.fmtDist(td), Graphics.TEXT_JUSTIFY_LEFT);
        }

        // textos de abajo
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (best != null) {
            dc.setColor(C_MAGENTA, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[bx - 6, by - 17], [bx + 6, by - 17], [bx, by - 8]]);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.64, Graphics.FONT_SMALL, best[0], jc);
            dc.drawText(cx, h * 0.745, Graphics.FONT_TINY,
                        best[4].toNumber().toString() + "m  " + Geo.fmtDist(best[3]), jc);
            dc.drawText(cx, h * 0.835, Graphics.FONT_TINY,
                        best[1].toNumber().toString() + "° " + Geo.cardinal(best[1]) + "  "
                        + fmtAng(best[2]), jc);
        } else if (sunTarget) {
            dc.drawText(cx, h * 0.64, Graphics.FONT_SMALL, "Sol", jc);
            var ev = pano.sunEvent;
            if (ev != null) {
                dc.drawText(cx, h * 0.745, Graphics.FONT_TINY, ev[0] + " " + Sun.hhmm(ev[1]), jc);
            }
            dc.drawText(cx, h * 0.835, Graphics.FONT_TINY,
                        sunNow[0].toNumber().toString() + "° " + Geo.cardinal(sunNow[0]) + "  "
                        + fmtAng(sunNow[1]), jc);
        } else {
            dc.drawText(cx, h * 0.745, Graphics.FONT_TINY,
                        H.toNumber().toString() + "° " + Geo.cardinal(H) + "  " + fmtAng(P), jc);
        }

        drawFooter(dc, w, h, fg);
    }

    function drawFooter(dc, w, h, fg) {
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var s = null;
        if (areaRunning) {
            s = "Zona " + store.done + "/" + store.total;
        } else if (msg != null && tick < msgUntil) {
            s = msg;
        } else if (waitingTiles || pano.computing()) {
            s = "Actualizando…";
        } else if (!hasCompass) {
            s = "Sin brújula: UP/DOWN";
        }
        if (s != null) {
            dc.setColor(dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 0.92, Graphics.FONT_XTINY, s, jc);
        }
    }

    function drawStatus(dc, w, h, fg) {
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.35, Graphics.FONT_MEDIUM, "Horizonte", jc);
        var s;
        if (lat == null) {
            s = "Buscando GPS…";
        } else if (waitingTiles) {
            s = "Relieve " + store.done + "/" + store.total;
        } else if (pano.computing()) {
            s = "Calculando " + pano.progress() + "%";
        } else {
            s = "Preparando…";
        }
        dc.drawText(w / 2, h * 0.52, Graphics.FONT_SMALL, s, jc);
        drawFooter(dc, w, h, fg);
    }

    function clampY(y, h) {
        if (y < -h) { y = -h; }
        if (y > 2 * h) { y = 2 * h; }
        return y.toNumber();
    }

    function fmtAng(a) {
        return (a >= 0 ? "+" : "") + a.format("%.1f") + "°";
    }

    // distancia al terreno que hay bajo la mira
    function terrainDist(H, P) {
        var ri = (Geo.norm360(H) + 0.5).toNumber() % 360;
        var n = pano.cnt[ri];
        var b = ri * Cfg.MAXR;
        for (var k = 0; k < n; k++) {
            if (pano.ang[b + k] >= P) { return pano.dist[b + k]; }
        }
        return null;
    }
}
