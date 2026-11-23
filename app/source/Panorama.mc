import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Cálculo de crestas (por rayos) y cumbres visibles, repartido en trocitos
// para no disparar el watchdog del reloj.
class Panorama {
    var store;
    var ang;      // grados, [rayo * MAXR + k], crestas de cerca a lejos (ángulo creciente)
    var dist;     // m
    var cnt;      // nº de crestas por rayo
    var link;     // índice de la cresta enlazada en el rayo siguiente (-1 = ninguna)
    var vis = []; // cumbres visibles: [nombre, az, elevación°, dist m, altura m]
    var sunEvent = null;  // ["Puesta"/"Salida", t]

    var lat0 = 0.0;
    var lon0 = 0.0;
    var h0 = 0.0;
    var mLat = 0.0;
    var mLon = 0.0;
    var cosLat = 1.0;

    var phase = 0;        // 0 parado, 1 rayos, 2 cumbres, 3 sol
    var ray = 0;
    var ready = false;
    var plist = [];
    var pIdx = 0;
    var newVis = [];
    var sunT0 = 0;
    var sunIt = 0;
    var sunAbove0 = false;

    function initialize(s) {
        store = s;
        var n = Cfg.RAYS * Cfg.MAXR;
        ang = new [n];
        dist = new [n];
        link = new [n];
        cnt = new [Cfg.RAYS];
        for (var i = 0; i < Cfg.RAYS; i++) { cnt[i] = 0; }
    }

    function computing() {
        return phase != 0;
    }

    function progress() {
        if (phase == 1) { return ray * 100 / Cfg.RAYS; }
        return 100;
    }

    function start(lat, lon, h) {
        lat0 = lat;
        lon0 = lon;
        h0 = h;
        cosLat = Math.cos(lat * Geo.D2R);
        mLat = 1.0 / 111320.0;
        mLon = 1.0 / (111320.0 * cosLat);
        ray = 0;
        phase = 1;
    }

    // Llamar en cada tick del temporizador
    function step(withSun) {
        if (phase == 1) {
            var end = ray + Cfg.RAYS_PER_TICK;
            if (end > Cfg.RAYS) { end = Cfg.RAYS; }
            for (var r = ray; r < end; r++) {
                computeRay(r);
                if (r > 0) { linkRay(r - 1); }
            }
            ray = end;
            if (ray >= Cfg.RAYS) {
                linkRay(Cfg.RAYS - 1);
                ready = true;
                startPeaks();
                phase = 2;
            }
        } else if (phase == 2) {
            var end = pIdx + 40;
            if (end > plist.size()) { end = plist.size(); }
            for (var i = pIdx; i < end; i++) { checkPeak(plist[i]); }
            pIdx = end;
            if (pIdx >= plist.size()) {
                vis = newVis;
                plist = [];
                if (withSun) { startSun(); phase = 3; } else { phase = 0; }
            }
        } else if (phase == 3) {
            sunStep();
        }
    }

    function computeRay(r) {
        var az = r * (360.0 / Cfg.RAYS) * Geo.D2R;
        var dn = Math.cos(az) * mLat;
        var de = Math.sin(az) * mLon;
        var d = 60.0;
        var maxT = -1.0e9;
        var vis1 = false;
        var cT = 0.0;
        var cD = 0.0;
        var n = 0;
        var base = r * Cfg.MAXR;
        var h = h0;
        var la = lat0;
        var lo = lon0;
        var st = store;
        while (d <= Cfg.MAX_DIST) {
            var e = st.elevAt(d < Cfg.FINE_RADIUS ? 1 : 0, la + dn * d, lo + de * d);
            var t = (e - h - d * d * Cfg.K_CURV) / d;
            if (t > maxT) {
                maxT = t;
                cT = t;
                cD = d;
                vis1 = true;
            } else if (vis1) {
                n = rec(base, n, cT, cD);
                vis1 = false;
            }
            if (d < 2000.0) { d += 60.0; } else { d += d * 0.03; }
        }
        if (vis1) { n = rec(base, n, cT, cD); }
        cnt[r] = n;
    }

    function rec(base, n, t, d) {
        var a = Math.atan(t) * Geo.R2D;
        if (n > 0 && a - ang[base + n - 1] < 0.1) {
            ang[base + n - 1] = a;
            dist[base + n - 1] = d;
            return n;
        }
        if (n < Cfg.MAXR) {
            ang[base + n] = a;
            dist[base + n] = d;
            return n + 1;
        }
        ang[base + n - 1] = a;
        dist[base + n - 1] = d;
        return n;
    }

    function linkRay(r) {
        var r2 = (r + 1) % Cfg.RAYS;
        var b1 = r * Cfg.MAXR;
        var b2 = r2 * Cfg.MAXR;
        var n1 = cnt[r];
        var n2 = cnt[r2];
        for (var k = 0; k < n1; k++) {
            var d1 = dist[b1 + k];
            var best = -1;
            var bestR = 0.25;
            for (var j = 0; j < n2; j++) {
                var rr = (dist[b2 + j] - d1).abs() / d1;
                if (rr < bestR) {
                    bestR = rr;
                    best = j;
                }
            }
            link[b1 + k] = best;
        }
    }

    // ángulo del horizonte (última cresta) para un azimut
    function skylineAt(az) {
        var r = (Geo.norm360(az) * Cfg.RAYS / 360.0 + 0.5).toNumber() % Cfg.RAYS;
        var n = cnt[r];
        if (n == 0) { return 0.0; }
        return ang[r * Cfg.MAXR + n - 1];
    }

    function startPeaks() {
        plist = [];
        var vs = store.peaks.values();
        for (var i = 0; i < vs.size(); i++) { plist.addAll(vs[i]); }
        pIdx = 0;
        newVis = [];
    }

    function checkPeak(p) {
        if (newVis.size() >= 300) { return; }
        var dN = (p[1] - lat0) * 111320.0;
        var dE = (p[2] - lon0) * 111320.0 * cosLat;
        var d = Math.sqrt(dN * dN + dE * dE);
        if (d < 150.0 || d > Cfg.MAX_DIST) { return; }
        var az = Geo.norm360(Math.atan2(dE, dN) * Geo.R2D);
        var a = Math.atan((p[3] - h0 - d * d * Cfg.K_CURV) / d) * Geo.R2D;
        var r = (az * Cfg.RAYS / 360.0 + 0.5).toNumber() % Cfg.RAYS;
        var margin = d * 0.2;
        if (margin < 300.0) { margin = 300.0; }
        var lim = d - margin;
        var blk = -90.0;
        for (var q = -1; q <= 1; q++) {
            var rr = (r + q + Cfg.RAYS) % Cfg.RAYS;
            var b = rr * Cfg.MAXR;
            for (var k = 0; k < cnt[rr]; k++) {
                if (dist[b + k] < lim && ang[b + k] > blk) { blk = ang[b + k]; }
            }
        }
        if (a >= blk - 0.2) {
            newVis.add([p[0], az, a, d, p[3]]);
        }
    }

    function startSun() {
        sunT0 = Time.now().value();
        sunIt = 0;
        sunEvent = null;
    }

    // Busca cuándo el sol cruza la cresta real (pasos de 2 min, hasta 24 h)
    function sunStep() {
        for (var i = 0; i < 40; i++) {
            var t = sunT0 + sunIt * 120;
            var sp = Sun.pos(t, lat0, lon0);
            var above = sp[1] > skylineAt(sp[0]);
            if (sunIt == 0) {
                sunAbove0 = above;
            } else if (above != sunAbove0) {
                sunEvent = [sunAbove0 ? "Puesta" : "Salida", t];
                phase = 0;
                return;
            }
            sunIt++;
            if (sunIt > 720) {
                phase = 0;
                return;
            }
        }
    }
}
