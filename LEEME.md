# Horizonte: qué cumbre es esa, en tu Garmin

Clon propio de PeakHorizon para Connect IQ, pensado para España (península, Baleares y Canarias, más los bordes de Portugal, Francia y Andorra). Todo funciona dentro de la app del reloj, sin apps extra en el móvil. Los datos llegan a través de Garmin Connect desde tu propia web de GitHub Pages. Si algún día vas sin cobertura, puedes bajar zonas desde el menú del reloj, pero no hace falta.

```
horizonte/
├── app/     → la app de Connect IQ (Monkey C)
├── datos/   → scripts de Python que generan el relieve y las cumbres
└── .github/ → automatización que los genera y publica en GitHub Pages
```

## Cómo funciona

- **Relieve**: Copernicus DEM GLO-90, cortado en teselas de 50×50 muestras.
  - Gruesas: 0,5°, con rejilla de unos 1 km. Se usan de 10 a 50 km.
  - Finas: 0,1°, con rejilla de unos 200 m. Se usan hasta 10 km.
  - Cada tesela ocupa unos 3,5 KB.
- **Cumbres**: OpenStreetMap (`natural=peak/volcano` con nombre). Se guardan las 150 más "aisladas" de cada tesela de 0,5°.
- **El reloj** descarga las teselas que tiene alrededor, las guarda en caché y calcula él mismo las crestas. Lanza 360 rayos hasta 50 km, con curvatura terrestre y refracción. Después decide qué cumbres se ven. Como el cálculo es siempre local, funciona igual con conexión que sin ella. Recalcula cada 150 m que te mueves.
- **Sol**: posición actual y hora real de puesta o salida por detrás de la cresta, no del horizonte plano.

---

## 1. Generar los datos (sin ordenador, en GitHub)

Los datos se generan y se publican en tu propia cuenta de GitHub. El reloj solo habla con **tu** web a través de Garmin Connect en el móvil: nada de Overpass, Open-Meteo ni otras apps en el día a día.

1. Crea en GitHub un repo **público** llamado `horizonte`.
2. Sube el contenido de esta carpeta a la raíz del repo: `app/`, `datos/`, `.github/` y `LEEME.md`.
   - Desde el PC: *Add file → Upload files* y arrastra todo.
   - Si la carpeta `.github` no se sube (a veces se salta por empezar por punto), créala a mano: *Add file → Create new file*, nombre `.github/workflows/datos.yml`, y pega dentro el contenido del archivo.
3. Ve a **Settings → Pages → Source: GitHub Actions**.
4. Ve a **Actions → Generar datos → Run workflow**. Pon `galicia` para probar (unos 10 min) o `espana` (1–2 h).
5. Cuando termine en verde, abre `https://TU_USUARIO.github.io/horizonte/c/86_-17.json`. Si ves texto con `"b":` y `"e":`, ya está publicado. Esa es la zona de Ferrol.

Si quieres añadir regiones o regenerar, vuelve a darle a *Run workflow*. El relieve ya descargado se reaprovecha.

> Opcional, en el PC: `python datos/vista_previa.py 43.4706 -8.1600 --web datos/web` dibuja el panorama con el mismo cálculo que el reloj, si generas los datos en local con `python datos/generar_datos.py`.

## 3. Compilar e instalar la app

1. Instala **VS Code**, el **Connect IQ SDK Manager** (descarga el último SDK y los dispositivos Fenix 7 Pro) y la extensión **Monkey C**.
2. En VS Code, ejecuta `Monkey C: Generate a Developer Key`.
3. Abre `app/source/Cfg.mc` y cambia `TU_USUARIO` en `BASE_URL` por tu usuario de GitHub.
4. Abre la carpeta `app/`.
5. Prueba en el simulador con `Monkey C: Run` y elige *fenix7pronowifi*.
   - Ve a Simulation → Set Position y pon, por ejemplo, 43.4706, -8.1600.
   - En el simulador no hay brújula: gira la vista con UP y DOWN.
6. Para el reloj: ejecuta `Monkey C: Build for Device` → *fenix7pronowifi*. Conecta el Fenix por USB y copia el `.prg` a `GARMIN/APPS/`.

> Tu Fenix 7 Pro Solar sin Wi-Fi es `fenix7pronowifi` (el de 51 mm es `fenix7xpronowifi`). Si el SDK se queja de algún id de producto en `manifest.xml`, bórralo de la lista.

## 4. Uso

- **Sujeción**: lleva el reloj plano, como cuando miras la hora, y apunta con las 12 hacia la montaña. Gira el cuerpo para recorrer el horizonte.
- **Mirar arriba o abajo**: inclina la muñeca. Si va al revés, activa *Invertir inclinación* en el menú.
- **La mira** muestra la cumbre más cercana con su nombre, altura, distancia, rumbo y ángulo. El número verde junto a la mira es la distancia al terreno que tienes debajo.
- **START o mantener UP** abre el menú:
  - Tema oscuro
  - Sol
  - Invertir inclinación
  - Tamaño zona
  - **Descargar zona aquí**
  - Borrar
  - Recalcular
- **Zona sin conexión**: con el móvil cerca, usa *Descargar zona aquí* antes de ir al monte. Baja la zona alrededor de tu posición más el relieve lejano de alrededor.
  - 20×20 km ocupa unos 150 KB.
  - 50×50 km puede no caber en la memoria de la app. Si no cabe, el reloj avisa con "Memoria llena".

## 5. Si algo falla

| Síntoma | Solución |
|---|---|
| Errores de tipos al compilar | En la configuración de VS Code, pon **Monkey C: Type Check Level** en *Off* |
| `Watchdog Tripped Error` | Baja `RAYS_PER_TICK` en `Cfg.mc` a 2 o 3 |
| `Out of memory` | Baja `MAXR` a 8 o `FINE_RADIUS` a 7000 |
| "Sin conexión: faltan N" | El móvil no está conectado o Garmin Connect está cerrado. Se reintenta solo al moverte, o con *Recalcular* |
| La vista no coincide con el paisaje | Calibra la brújula en los ajustes del reloj (Sensores → Brújula) |
| Cumbres que sobran o faltan | Ajusta `PEAKS_PER_TILE` en `generar_datos.py` y regenera |

Ajustes de vista en `Cfg.mc`:
- `HFOV`: grados que caben de ancho en la pantalla.
- `VSCALE`: exageración vertical.
- `TARGET_DEG`: lo cerca que tiene que estar una cumbre de la mira para seleccionarla.

Fuentes de datos: Copernicus DEM GLO-90 (© DLR e.V. / Airbus, ESA) y © colaboradores de OpenStreetMap (ODbL).
