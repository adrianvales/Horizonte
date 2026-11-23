import Toybox.Lang;
import Toybox.Math;
import Toybox.Application;
import Toybox.Communications;
import Toybox.StringUtil;

// Teselas de relieve: descarga (vía móvil), caché en el reloj, zonas sin conexión
// y muestreo de alturas.
class TerrainStore {
    var tiles = {};       // clave numérica -> [ByteArray, base, paso] ; null = mar
    var peaks = {};       // clave numérica (nivel grueso) -> [[nombre, lat, lon, ele], ...]
    var queue = [];       // [[claveTexto, claveNum, modo]]  modo 0 = cargar, 1 = guardar zona
    var busy = false;
    var curItem = null;
    var total = 0;
    var done = 0;
    var failed = 0;
    var areaMode = false;
    var areaFull = false;
    var listener;
    var _lk = -1;
    var _lt = null;

    function initialize(l) {
        listener = l;
    }

    function isRunning() {
        return busy || queue.size() > 0;
    }

    function numKey(level, ti, tj) {
        return level * 1000000 + (ti + 500) * 1000 + (tj + 500);
    }

    function strKey(level, ti, tj) {
        return (level == 0 ? "c/" : "f/") + ti.toString() + "_" + tj.toString();
    }

    // Teselas necesarias: finas en rFine metros y gruesas en rCoarse metros
    function keysAround(lat, lon, rFine, rCoarse) {
        var res = [];
        addRange(res, 1, lat, lon, rFine, Cfg.TILE_F, Cfg.STEP_F);
        addRange(res, 0, lat, lon, rCoarse, Cfg.TILE_C, Cfg.STEP_C);
        return res;
    }

    function addRange(res, level, lat, lon, r, tile, step) {
        var dLat = r / 111320.0 + 2 * step;
        var dLon = r / (111320.0 * Math.cos(lat * Geo.D2R)) + 2 * step;
        var i0 = Math.floor((lat - dLat) / tile).toNumber();
        var i1 = Math.floor((lat + dLat) / tile).toNumber();
        var j0 = Math.floor((lon - dLon) / tile).toNumber();
        var j1 = Math.floor((lon + dLon) / tile).toNumber();
        // primero las más cercanas al centro
        var ci = Math.floor(lat / tile).toNumber();
        var cj = Math.floor(lon / tile).toNumber();
        var maxRing = (i1 - i0 > j1 - j0) ? (i1 - i0) : (j1 - j0);
        for (var ring = 0; ring <= maxRing; ring++) {
            for (var i = i0; i <= i1; i++) {
                for (var j = j0; j <= j1; j++) {
                    var di = (i - ci).abs();
                    var dj = (j - cj).abs();
                    var rg = di > dj ? di : dj;
                    if (rg == ring) {
                        res.add([strKey(level, i, j), numKey(level, i, j), level]);
                    }
                }
            }
        }
    }

    // Carga en memoria lo necesario para (lat, lon): primero del reloj, luego del móvil.
    function ensure(lat, lon) {
        var need = keysAround(lat, lon, Cfg.FINE_RADIUS, Cfg.MAX_DIST);
        var needSet = {};
        for (var i = 0; i < need.size(); i++) {
            needSet[need[i][1]] = true;
        }
        var ks = tiles.keys();
        for (var i = 0; i < ks.size(); i++) {
            if (!needSet.hasKey(ks[i])) {
                tiles.remove(ks[i]);
                peaks.remove(ks[i]);
            }
        }
        _lk = -1;
        _lt = null;
        queue = [];
        areaMode = false;
        failed = 0;
        done = 0;
        for (var i = 0; i < need.size(); i++) {
            var k = need[i];
            if (tiles.hasKey(k[1])) { continue; }
            var d = Application.Storage.getValue("T" + k[0]);
            if (d != null) {
                put(k[1], k[2], d);
            } else {
                queue.add([k[0], k[1], 0]);
            }
        }
        total = queue.size();
        next();
    }

    // Descarga y guarda en el reloj una zona de km x km (más el relieve lejano alrededor)
    function downloadArea(lat, lon, km) {
        var half = km * 500.0;
        var need = keysAround(lat, lon, half, half + Cfg.MAX_DIST);
        queue = [];
        areaMode = true;
        areaFull = false;
        failed = 0;
        done = 0;
        var ak = getArr("ak");
        var ck = getArr("ck");
        for (var i = 0; i < need.size(); i++) {
            var key = "T" + need[i][0];
            if (ak.indexOf(key) >= 0) { continue; }
            if (Application.Storage.getValue(key) != null) {
                ak.add(key);
                ck.remove(key);
                continue;
            }
            queue.add([need[i][0], need[i][1], 1]);
        }
        setArr("ak", ak);
        setArr("ck", ck);
        total = queue.size();
        next();
    }

    function clearAll() {
        var lists = [getArr("ak"), getArr("ck")];
        for (var l = 0; l < 2; l++) {
            for (var i = 0; i < lists[l].size(); i++) {
                Application.Storage.deleteValue(lists[l][i]);
            }
        }
        setArr("ak", []);
        setArr("ck", []);
    }

    function areaCount() {
        return getArr("ak").size();
    }

    function put(nk, level, d) {
        _lk = -1;
        _lt = null;
        if (d instanceof Dictionary && d.hasKey("e")) {
            var bytes = StringUtil.convertEncodedString(d["e"], {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            });
            tiles[nk] = [bytes, d["b"], d["q"]];
            if (level == 0 && d.hasKey("p") && d["p"] != null) {
                peaks[nk] = d["p"];
            }
        } else {
            tiles[nk] = null;   // mar
        }
    }

    function next() {
        if (busy) { return; }
        if (queue.size() == 0) {
            if (listener != null) {
                if (areaMode) { listener.onAreaDone(); } else { listener.onTilesReady(); }
            }
            return;
        }
        curItem = queue[0];
        queue = queue.slice(1, null);
        busy = true;
        Communications.makeWebRequest(Cfg.BASE_URL + curItem[0] + ".json", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onResp));
    }

    function onResp(code, data) {
        busy = false;
        var it = curItem;
        done++;
        var level = it[1] / 1000000;
        if (code == 200 && data instanceof Dictionary) {
            save(it, data);
            if (it[2] == 0) { put(it[1], level, data); }
        } else if (code == 404) {
            save(it, {"z" => 1});
            if (it[2] == 0) { put(it[1], level, null); }
        } else {
            failed++;   // sin conexión u otro error: se reintentará más tarde
        }
        if (listener != null) { listener.onStoreProgress(); }
        next();
    }

    function save(it, data) {
        var key = "T" + it[0];
        try {
            Application.Storage.setValue(key, data);
        } catch (e) {
            if (it[2] == 1) {
                areaFull = true;   // memoria del reloj llena: se para la descarga de la zona
                queue = [];
                return;
            }
            // caché normal llena: liberar la mitad y reintentar una vez
            var ck0 = getArr("ck");
            var nDel = ck0.size() / 2 + 1;
            for (var i = 0; i < nDel && i < ck0.size(); i++) {
                Application.Storage.deleteValue(ck0[i]);
            }
            setArr("ck", ck0.slice(nDel < ck0.size() ? nDel : ck0.size(), null));
            try {
                Application.Storage.setValue(key, data);
            } catch (e2) {
                return;
            }
        }
        var ak = getArr("ak");
        var ck = getArr("ck");
        if (it[2] == 1) {
            if (ak.indexOf(key) < 0) { ak.add(key); setArr("ak", ak); }
            if (ck.indexOf(key) >= 0) { ck.remove(key); setArr("ck", ck); }
        } else if (ak.indexOf(key) < 0 && ck.indexOf(key) < 0) {
            ck.add(key);
            while (ck.size() > Cfg.MAX_CACHE) {
                Application.Storage.deleteValue(ck[0]);
                ck = ck.slice(1, null);
            }
            setArr("ck", ck);
        }
    }

    function getArr(name) {
        var a = Application.Storage.getValue(name);
        return (a == null) ? [] : a;
    }

    function setArr(name, a) {
        try {
            Application.Storage.setValue(name, a);
        } catch (e) {
        }
    }

    // ----------------- muestreo -----------------
    function sample(level, gi, gj) {
        var ti = gi / 50;
        if (gi < 0 && ti * 50 != gi) { ti -= 1; }
        var tj = gj / 50;
        if (gj < 0 && tj * 50 != gj) { tj -= 1; }
        var k = level * 1000000 + (ti + 500) * 1000 + (tj + 500);
        var t;
        if (k == _lk) {
            t = _lt;
        } else {
            t = tiles[k];
            _lk = k;
            _lt = t;
        }
        if (t == null) { return 0; }
        return t[1] + t[2] * t[0][(gi - ti * 50) * 50 + (gj - tj * 50)];
    }

    // altura (m) interpolada; level 1 = fino, 0 = grueso
    function elevAt(level, lat, lon) {
        var step = (level == 1) ? Cfg.STEP_F : Cfg.STEP_C;
        var fi = lat / step;
        var fj = lon / step;
        var gi = fi.toNumber();
        if (fi < gi) { gi -= 1; }
        var gj = fj.toNumber();
        if (fj < gj) { gj -= 1; }
        var a = fi - gi;
        var b = fj - gj;
        var e00 = sample(level, gi, gj);
        var e01 = sample(level, gi, gj + 1);
        var e10 = sample(level, gi + 1, gj);
        var e11 = sample(level, gi + 1, gj + 1);
        return (e00 * (1.0 - b) + e01 * b) * (1.0 - a) + (e10 * (1.0 - b) + e11 * b) * a;
    }
}
