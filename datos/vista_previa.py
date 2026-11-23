#!/usr/bin/env python3
"""
Vista previa en el PC: calcula el panorama EXACTAMENTE con el mismo algoritmo que el reloj
(teselas, rayos, crestas, visibilidad de cumbres) y lo dibuja en un PNG.
Sirve para comprobar los datos antes de subirlos.

  python vista_previa.py 43.4706 -8.1600            # lat lon (p. ej. monte de Ferrol)
  python vista_previa.py 43.4706 -8.1600 --web web --png vista.png
"""
import argparse
import base64
import json
import math
import os

N = 50
LV = {0: ("c", 0.01), 1: ("f", 0.002)}
FINE_RADIUS = 10000.0
MAX_DIST = 50000.0
RAYS = 360
MAXR = 12
K = (1 - 0.13) / (2 * 6371000.0)
GAP = math.radians(0.1)


class Store:
    def __init__(self, web):
        self.web = web
        self.tiles = {}
        self.peaks = []

    def load(self, lvl, ti, tj):
        k = (lvl, ti, tj)
        if k in self.tiles:
            return self.tiles[k]
        name, _ = LV[lvl]
        p = os.path.join(self.web, name, f"{ti}_{tj}.json")
        t = None
        if os.path.exists(p):
            d = json.load(open(p, encoding="utf-8"))
            t = (base64.b64decode(d["e"]), d["b"], d["q"])
            if lvl == 0:
                self.peaks += d.get("p", [])
        self.tiles[k] = t
        return t

    def sample(self, lvl, gi, gj):
        t = self.load(lvl, gi // N, gj // N)
        if t is None:
            return 0
        return t[1] + t[2] * t[0][(gi % N) * N + (gj % N)]

    def elev(self, lvl, lat, lon):
        step = LV[lvl][1]
        fi, fj = lat / step, lon / step
        gi, gj = math.floor(fi), math.floor(fj)
        a, b = fi - gi, fj - gj
        e00 = self.sample(lvl, gi, gj)
        e01 = self.sample(lvl, gi, gj + 1)
        e10 = self.sample(lvl, gi + 1, gj)
        e11 = self.sample(lvl, gi + 1, gj + 1)
        return (e00 * (1 - b) + e01 * b) * (1 - a) + (e10 * (1 - b) + e11 * b) * a


def panorama(st, lat0, lon0, h0):
    ang = [[] for _ in range(RAYS)]
    dist = [[] for _ in range(RAYS)]
    mlat = 1 / 111320.0
    mlon = 1 / (111320.0 * math.cos(math.radians(lat0)))
    for r in range(RAYS):
        az = math.radians(r * 360.0 / RAYS)
        dn, de = math.cos(az), math.sin(az)
        d = 60.0
        maxt = -1e9
        vis = False
        ct = cd = 0.0
        A, D = ang[r], dist[r]

        def rec(ct, cd):
            a = math.atan(ct)
            if A and a - A[-1] < GAP:
                A[-1], D[-1] = a, cd
            elif len(A) < MAXR:
                A.append(a); D.append(cd)
            else:
                A[-1], D[-1] = a, cd
        while d <= MAX_DIST:
            lv = 1 if d < FINE_RADIUS else 0
            e = st.elev(lv, lat0 + dn * d * mlat, lon0 + de * d * mlon)
            t = (e - h0 - d * d * K) / d
            if t > maxt:
                maxt, ct, cd, vis = t, t, d, True
            elif vis:
                rec(ct, cd); vis = False
            d += 60.0 if d < 2000 else d * 0.03
        if vis:
            rec(ct, cd)
    return ang, dist


def visible_peaks(st, ang, dist, lat0, lon0, h0):
    out = []
    c = math.cos(math.radians(lat0))
    for name, plat, plon, pele in st.peaks:
        dn = (plat - lat0) * 111320.0
        de = (plon - lon0) * 111320.0 * c
        d = math.hypot(dn, de)
        if d < 150 or d > MAX_DIST:
            continue
        az = math.degrees(math.atan2(de, dn)) % 360
        a = math.atan((pele - h0 - d * d * K) / d)
        r = int(round(az * RAYS / 360.0)) % RAYS
        blk = -10.0
        for rr in (r - 1, r, r + 1):
            rr %= RAYS
            for aa, dd in zip(ang[rr], dist[rr]):
                if dd < d - max(300.0, 0.2 * d) and aa > blk:
                    blk = aa
        if a >= blk - math.radians(0.2):
            out.append((name, az, math.degrees(a), d, pele))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lat", type=float)
    ap.add_argument("lon", type=float)
    ap.add_argument("--web", default="web")
    ap.add_argument("--png", default="vista_previa.png")
    a = ap.parse_args()
    st = Store(a.web)
    # cargar teselas gruesas en 50 km para tener las cumbres
    dlat = MAX_DIST / 111320.0
    dlon = MAX_DIST / (111320.0 * math.cos(math.radians(a.lat)))
    for ti in range(math.floor((a.lat - dlat) / 0.5), math.floor((a.lat + dlat) / 0.5) + 1):
        for tj in range(math.floor((a.lon - dlon) / 0.5), math.floor((a.lon + dlon) / 0.5) + 1):
            st.load(0, ti, tj)
    h0 = st.elev(1, a.lat, a.lon) + 2.0
    ang, dist = panorama(st, a.lat, a.lon, h0)
    pk = visible_peaks(st, ang, dist, a.lat, a.lon, h0)
    print(f"Altura observador (MDT+2 m): {h0:.0f} m · cumbres visibles: {len(pk)}")
    for name, az, el, d, e in sorted(pk, key=lambda x: x[3])[:25]:
        print(f"  {name:28s} {e:5.0f} m {d / 1000:5.1f} km  az {az:5.1f}°  {el:+.2f}°")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(24, 4), dpi=100)
    for r in range(RAYS):
        for aa, dd in zip(ang[r], dist[r]):
            ax.plot(r * 360 / RAYS, math.degrees(aa), ".", ms=1.5,
                    color=plt.cm.viridis(min(1, dd / MAX_DIST)))
    sky = [math.degrees(ang[r][-1]) if ang[r] else 0 for r in range(RAYS)]
    ax.plot([r * 360 / RAYS for r in range(RAYS)], sky, "k-", lw=1)
    for name, az, el, d, e in pk:
        ax.plot(az, el, "v", color="purple", ms=4)
        ax.text(az, el + 0.3, name, rotation=90, fontsize=6, ha="center", va="bottom")
    ax.set_xlim(0, 360)
    ax.set_xticks(range(0, 361, 45))
    ax.set_xticklabels(["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"])
    ax.set_ylabel("elevación (°)")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(a.png)
    print("PNG ->", a.png)


if __name__ == "__main__":
    main()
