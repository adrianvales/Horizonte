import Toybox.Lang;
import Toybox.Math;

// ===================== CONFIGURACIÓN =====================
module Cfg {
    // >>> CAMBIA ESTO por la URL de tu GitHub Pages (con la barra final) <<<
    const BASE_URL = "https://TU_USUARIO.github.io/horizonte/";

    const N = 50;                    // muestras por lado de cada tesela
    const STEP_C = 0.01;             // grados, nivel grueso (~1 km)
    const STEP_F = 0.002;            // grados, nivel fino (~200 m)
    const TILE_C = 0.5;              // grados por tesela gruesa
    const TILE_F = 0.1;              // grados por tesela fina

    const FINE_RADIUS = 10000.0;     // m: hasta aquí se usa el nivel fino
    const MAX_DIST = 50000.0;        // m: alcance de las crestas
    const RAYS = 360;                // rayos (1 por grado)
    const MAXR = 12;                 // crestas guardadas por rayo
    const RAYS_PER_TICK = 4;         // bájalo a 2-3 si sale "Watchdog Tripped"
    const RECALC_DIST = 150.0;       // m que hay que moverse para recalcular
    const EYE = 2.0;                 // m sobre el terreno

    const HFOV = 60.0;               // grados de ancho de pantalla
    const VSCALE = 1.6;              // exageración vertical
    const TARGET_DEG = 4.0;          // margen para "apuntar" a una cumbre

    const MAX_CACHE = 40;            // teselas cacheadas (aparte de las zonas)
    const K_CURV = 6.828e-8;         // (1 - 0.13) / (2 * 6371000): curvatura + refracción
}

module Geo {
    const D2R = 0.017453292519943295;
    const R2D = 57.29577951308232;

    function wrap180(a) {
        var x = a - 360.0 * Math.floor((a + 180.0) / 360.0);
        return x;
    }

    function norm360(a) {
        return a - 360.0 * Math.floor(a / 360.0);
    }

    // división entera hacia -infinito
    function fdiv(a, b) {
        var q = a / b;
        if (a < 0 && q * b != a) { q -= 1; }
        return q;
    }

    function cardinal(az) {
        var names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
        var i = ((norm360(az) + 11.25) / 22.5).toNumber() % 16;
        return names[i];
    }

    function fmtDist(d) {
        if (d < 10000.0) { return (d / 1000.0).format("%.1f") + "km"; }
        return (d / 1000.0 + 0.5).toNumber().toString() + "km";
    }
}
