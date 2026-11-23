#!/usr/bin/env python3
"""
Genera los datos de relieve y cumbres para la app Horizonte (Garmin Connect IQ).

Salida (carpeta ./web, lista para subir a GitHub Pages):
  web/c/{ti}_{tj}.json  -> teselas "gruesas": 0,5 x 0,5 grados, rejilla de 0,01 grados (~1 km)
                           + lista de cumbres con nombre de OpenStreetMap
  web/f/{ti}_{tj}.json  -> teselas "finas": 0,1 x 0,1 grados, rejilla de 0,002 grados (~200 m)

Cada tesela tiene 50x50 muestras. Formato:
  {"b": base_m, "q": paso_m, "e": "<base64 de 2500 bytes>"}
  altura = b + q * byte ; los bytes van por filas de sur a norte, y de oeste a este.
  Muestra (fila r, col c) de la tesela (ti, tj) está en
      lat = (ti*50 + r) * paso_grados ,  lon = (tj*50 + c) * paso_grados
Las teselas que son todo mar no se escriben (el reloj interpreta 404 = mar = 0 m).

Fuentes:
  - Relieve: Copernicus DEM GLO-90 (bucket público de AWS, sin registro)
  - Cumbres: OpenStreetMap vía Overpass API (natural=peak / volcano con nombre)

Uso:
  pip install numpy scipy rasterio requests
  python generar_datos.py --region galicia      # prueba rápida
  python generar_datos.py --region espana       # península + Baleares + Canarias (+ bordes de PT/FR/AND)
"""
import argparse
import base64
import json
import math
import os
import sys
import time

import numpy as np
import requests

N = 50
LEVELS = {
    # nombre: (tamaño tesela en grados, paso en grados, teselas por grado)
    "c": (0.5, 0.01, 2),
    "f": (0.1, 0.002, 10),
}
REGIONS = {
    # (lat_min, lon_min, lat_max, lon_max)
    "galicia": [(41.5, -9.5, 44.0, -6.5)],
    "asturias": [(42.7, -7.4, 43.8, -4.4)],
    "pirineos": [(41.8, -2.0, 43.4, 3.4)],
    "peninsula": [(35.8, -9.6, 44.0, 4.4)],
    "canarias": [(27.5, -18.3, 29.5, -13.3)],
    "espana": [(35.8, -9.6, 44.0, 4.4), (27.5, -18.3, 29.5, -13.3)],
}
DEM_URL = ("https://copernicus-dem-90m.s3.amazonaws.com/"
           "Copernicus_DSM_COG_30_{n}_00_{e}_00_DEM/Copernicus_DSM_COG_30_{n}_00_{e}_00_DEM.tif")
# Varios servidores de Overpass: si uno no responde (p. ej. bloquea los servidores de GitHub) se usa otro
OVERPASS = [
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]

# Los servidores de GitHub no tienen IPv6: forzar IPv4 evita "Network is unreachable"
try:
    import urllib3.util.connection as _uc
    _uc.HAS_IPV6 = False
except Exception:
    pass
OVERPASS_FALLOS = 0
PEAKS_PER_TILE = 150
ISOLATION_MAX_KM = 10.0


def cell_name(la, lo):
    n = ("N%02d" % la) if la >= 0 else ("S%02d" % -la)
    e = ("E%03d" % lo) if lo >= 0 else ("W%03d" % -lo)
    return n, e


def download_dem(la, lo, cache):
    """Devuelve la ruta al GeoTIFF de la celda 1x1 grado (esquina SW la,lo) o None si es mar."""
    n, e = cell_name(la, lo)
    path = os.path.join(cache, f"{n}_{e}.tif")
    miss = path + ".mar"
    if os.path.exists(path):
        return path
    if os.path.exists(miss):
        return None
    url = DEM_URL.format(n=n, e=e)
    for intento in range(4):
        try:
            r = requests.get(url, timeout=120)
            if r.status_code in (403, 404):
                open(miss, "w").close()
                return None
            r.raise_for_status()
            with open(path + ".tmp", "wb") as f:
                f.write(r.content)
            os.replace(path + ".tmp", path)
            return path
        except requests.RequestException as ex:
            print(f"   reintento {intento + 1} {n}_{e}: {ex}")
            time.sleep(5 * (intento + 1))
    raise RuntimeError(f"No se pudo descargar {url}")


def read_dem(path):
    import rasterio
    with rasterio.open(path) as ds:
        arr = ds.read(1).astype(np.float32)
        nod = ds.nodata
        t = ds.transform
    if nod is not None:
        arr[arr == nod] = 0
    arr[~np.isfinite(arr)] = 0
    arr = np.maximum(arr, 0)
    return arr, t


def make_sampler(arr, t):
    """Interpolación bilineal en coordenadas geográficas."""
    from scipy.ndimage import map_coordinates

    def sample(lat, lon, a=arr):
        col = (lon - t.c) / t.a - 0.5
        row = (lat - t.f) / t.e - 0.5
        return map_coordinates(a, [row, col], order=1, mode="nearest")
    return sample


def encode(vals):
    vals = np.round(vals).astype(np.int32)
    b = int(vals.min())
    rng = int(vals.max()) - b
    q = max(1, int(math.ceil(rng / 255.0)))
    idx = np.clip(np.round((vals - b) / q), 0, 255).astype(np.uint8)
    return {"b": b, "q": q, "e": base64.b64encode(idx.tobytes()).decode("ascii")}


def tile_grid(level, ti, tj):
    size, step, _ = LEVELS[level]
    gi = ti * N + np.arange(N)
    gj = tj * N + np.arange(N)
    lat = gi * step
    lon = gj * step
    LON, LAT = np.meshgrid(lon, lat)  # filas = lat (sur->norte), cols = lon (oeste->este)
    return LAT, LON


def fetch_peaks(la, lo, cache):
    path = os.path.join(cache, f"peaks_{la}_{lo}.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    s, w, n, e = la, lo, la + 1, lo + 1
    q = f"""[out:json][timeout:180];
(
  node["natural"="peak"]["name"]({s},{w},{n},{e});
  node["natural"="volcano"]["name"]({s},{w},{n},{e});
);
out body;"""
    global OVERPASS, OVERPASS_FALLOS
    if OVERPASS_FALLOS >= 2:
        return []   # ningún servidor responde: no perder más tiempo
    for intento in range(2 * len(OVERPASS)):
        url = OVERPASS[0]
        try:
            r = requests.post(url, data={"data": q}, timeout=(15, 240),
                              headers={"User-Agent": "Horizonte-CIQ-datagen/1.0"})
            if r.status_code in (429, 504):
                raise requests.RequestException(f"HTTP {r.status_code}")
            r.raise_for_status()
            els = r.json().get("elements", [])
            out = []
            for el in els:
                tags = el.get("tags", {})
                name = tags.get("name")
                if not name:
                    continue
                out.append([name.strip(), el["lat"], el["lon"], parse_ele(tags.get("ele"))])
            with open(path, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False)
            time.sleep(1.0)
            OVERPASS_FALLOS = 0
            return out
        except (requests.RequestException, ValueError) as ex:
            print(f"   Overpass falló ({url.split('/')[2]}): {str(ex)[:120]}")
            OVERPASS = OVERPASS[1:] + OVERPASS[:1]   # probar el siguiente servidor
            time.sleep(3)
    OVERPASS_FALLOS += 1
    print(f"   AVISO: sin cumbres para la celda {la},{lo}")
    return []


def parse_ele(s):
    if not s:
        return None
    s = s.lower().replace("m", "").replace(",", ".").strip()
    # "1.134" (punto de miles) -> 1134
    if s.count(".") == 1 and len(s.split(".")[1]) == 3 and float(s) < 10:
        s = s.replace(".", "")
    try:
        v = float(s.split()[0].split(";")[0])
        return v if -50 < v < 9000 else None
    except (ValueError, IndexError):
        return None


def isolation(peaks):
    """Distancia (km) a la cumbre más alta más cercana, con tope en ISOLATION_MAX_KM."""
    from scipy.spatial import cKDTree
    if not peaks:
        return np.array([])
    lat = np.array([p[1] for p in peaks])
    lon = np.array([p[2] for p in peaks])
    ele = np.array([p[3] for p in peaks])
    xy = np.column_stack([lon * 111.32 * np.cos(np.radians(lat)), lat * 110.57])
    tree = cKDTree(xy)
    iso = np.full(len(peaks), ISOLATION_MAX_KM)
    for i, nb in enumerate(tree.query_ball_point(xy, ISOLATION_MAX_KM)):
        nb = np.array(nb)
        if nb.size == 0:
            continue
        higher = nb[(ele[nb] > ele[i]) | ((ele[nb] == ele[i]) & (nb < i))]
        if higher.size:
            d = np.hypot(*(xy[higher] - xy[i]).T)
            iso[i] = min(ISOLATION_MAX_KM, d.min())
    return iso


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="galicia", choices=REGIONS.keys())
    ap.add_argument("--out", default="web")
    ap.add_argument("--cache", default="cache")
    ap.add_argument("--sin-cumbres", action="store_true", help="no consultar Overpass")
    ap.add_argument("--margen", type=float, default=0.5, help="grados extra alrededor de la región")
    args = ap.parse_args()

    from scipy.ndimage import maximum_filter

    os.makedirs(args.cache, exist_ok=True)
    for lv in LEVELS:
        os.makedirs(os.path.join(args.out, lv), exist_ok=True)
    open(os.path.join(args.out, ".nojekyll"), "w").close()

    cells = set()
    for (a, b, c, d) in REGIONS[args.region]:
        m = args.margen
        for la in range(math.floor(a - m), math.ceil(c + m)):
            for lo in range(math.floor(b - m), math.ceil(d + m)):
                cells.add((la, lo))
    cells = sorted(cells)
    print(f"{len(cells)} celdas de 1x1 grado")

    coarse = {}        # (ti,tj) -> dict
    all_peaks = []     # [name, lat, lon, ele]
    nfine = 0
    for k, (la, lo) in enumerate(cells):
        path = download_dem(la, lo, args.cache)
        if path is None:
            continue
        arr, t = read_dem(path)
        if arr.max() <= 0:
            continue
        sample = make_sampler(arr, t)
        # ~0,01 grados de ventana para el nivel grueso (el máximo conserva las crestas)
        px_lat = abs(0.01 / t.e)
        px_lon = abs(0.01 / t.a)
        arr_max = maximum_filter(arr, size=(max(1, round(px_lat)), max(1, round(px_lon))))
        sample_max = make_sampler(arr_max, t)

        # finas
        for ti in range(la * 10, la * 10 + 10):
            for tj in range(lo * 10, lo * 10 + 10):
                LAT, LON = tile_grid("f", ti, tj)
                v = sample(LAT.ravel(), LON.ravel()).reshape(N, N)
                if v.max() <= 0.5:
                    continue
                with open(os.path.join(args.out, "f", f"{ti}_{tj}.json"), "w") as f:
                    json.dump(encode(v), f, separators=(",", ":"))
                nfine += 1
        # gruesas
        for ti in range(la * 2, la * 2 + 2):
            for tj in range(lo * 2, lo * 2 + 2):
                LAT, LON = tile_grid("c", ti, tj)
                v = sample_max(LAT.ravel(), LON.ravel()).reshape(N, N)
                if v.max() <= 0.5:
                    continue
                coarse[(ti, tj)] = encode(v)

        # cumbres de la celda
        if not args.sin_cumbres:
            pk = fetch_peaks(la, lo, args.cache)
            for name, plat, plon, pele in pk:
                if not (la <= plat < la + 1 and lo <= plon < lo + 1):
                    continue
                dem = float(sample(np.array([plat]), np.array([plon]))[0])
                if pele is None or abs(pele - dem) > 150:
                    pele = dem
                else:
                    pele = max(pele, dem)
                if pele <= 1:
                    continue
                all_peaks.append([name, plat, plon, pele])
        print(f"[{k + 1}/{len(cells)}] celda {la},{lo} ok  (finas: {nfine}, cumbres: {len(all_peaks)})")

    # Selección de cumbres por aislamiento
    iso = isolation(all_peaks)
    by_tile = {}
    for p, s in zip(all_peaks, iso):
        key = (math.floor(p[1] / 0.5), math.floor(p[2] / 0.5))
        by_tile.setdefault(key, []).append((s, p[3], p))
    for key, lst in by_tile.items():
        if key not in coarse:
            continue
        lst.sort(key=lambda x: (-x[0], -x[1]))
        coarse[key]["p"] = [[p[0][:28], round(p[1], 5), round(p[2], 5), int(round(p[3]))]
                            for _, _, p in lst[:PEAKS_PER_TILE]]

    for (ti, tj), d in coarse.items():
        d.setdefault("p", [])
        with open(os.path.join(args.out, "c", f"{ti}_{tj}.json"), "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, separators=(",", ":"))

    print(f"\nListo: {len(coarse)} teselas gruesas, {nfine} finas, {len(all_peaks)} cumbres -> {args.out}/")


if __name__ == "__main__":
    sys.exit(main())
