# Fase 3: integración web y móvil

Estado al 12 de noviembre de 2026 (Yoma 3.2.19).

## 1. Compartir biblioteca, favoritos, progreso e historial

**Punto de partida (decidido en la Fase 1).** La app usa el modelo local:

- su biblioteca, favoritos, progreso e historial están en el teléfono;
- no hay cuenta de tv.yoma.site en la app;
- lo único común entre la web y la app es **MyAnimeList**.

### Qué se comparte hoy, y cómo

| Dato | YomaTV app | YomaTV web | ¿Compartido? |
|---|---|---|---|
| Episodios vistos | Teléfono → MAL (sesión de la app) | Cuenta web → MAL | **Sí, a través de MAL**: las dos escriben en la misma lista si es la misma cuenta de MAL |
| «Viendo» / «Plan to watch» | MAL → biblioteca y vistos del teléfono | MAL → cuenta web | **Sí, a través de MAL** |
| Favoritos, guardados, colecciones | Teléfono | Cuenta web | No |
| Historial y posición dentro del episodio | Teléfono | Cuenta web | No |
| Descargas | Teléfono | Cola para PC | No (son de cada dispositivo) |

YomaShi funciona igual con la lista de manga de MAL (lectura y «Reading»).

### Opciones para compartir más

1. **Seguir con MAL como punto común (recomendada a corto plazo).**
   - No necesita cuentas nuevas ni servidor nuevo.
   - Comparte lo más importante (qué se ve o lee y hasta dónde) y ya funciona en las dos direcciones.
   - Límite: favoritos, colecciones e historial fino se quedan en cada sitio.
2. **Sincronización propia de Yoma con la identidad de MAL.**
   - Cómo funcionaría:
     - el servidor ya conoce la cuenta de MAL de cada teléfono por su `device_token`;
     - una acción nueva (`yoma_sync`) guardaría por cuenta de MAL un documento con favoritos, guardados, colecciones e historial;
     - la app y la web lo leerían y escribirían con la regla «gana el cambio más reciente de cada elemento».
   - Ventaja: no hace falta otra cuenta.
   - Coste:
     - tablas y acciones nuevas en el servidor;
     - resolver conflictos y borrados;
     - tráfico en un hosting gratuito con límites;
     - que la web lea esos datos en lugar de los de su cuenta.
   - Sería un proyecto propio, a hacer después de mover los servicios a `api.yoma.site` (sección 3).
3. **Volver a usar la cuenta web en la app.** No se recomienda: deshace la decisión de la Fase 1, vuelve a necesitar dos cuentas (web y MAL) y era la causa de las pantallas y colas duplicadas.

**Decisión pendiente:** quedarse con la opción 1 o encargar la opción 2 como proyecto aparte.

## 2. Funciones de la web en la app

| Función web | Necesita cuenta web | Estado en la app |
|---|---|---|
| **Horario / Temporada** | No (catálogo público) | **Hecho en la 3.2.19.** Botón «Horario de emisión» en YomaTV (detalle abajo) |
| Avisos de episodios nuevos | Sí, en la web | Ya existe en la app: el mantenimiento avisa de episodios nuevos de lo guardado (`AnimeEpisodeWatch`) |
| Estadísticas | Sí | YomaShi tiene estadísticas locales. YomaTV podría calcularlas de su historial local (episodios, horas, anime); propuesta pequeña |
| Colecciones | Sí | Solo en la web (ver opción 2 de la sección 1) |
| Radio | No | Sigue en la web; se abre desde «Más › YomaTV en la web». No aporta nada hacerla nativa |
| Cola para PC | Sí | Solo en la web; es para el descargador de Windows |

**Detalle del horario:**

- **Contenido.** Días de lunes a domingo, con «Hoy» seleccionado. Muestra el número de anime de cada día, la portada, el último episodio y la próxima emisión estimada cuando cae en esta semana.
- **Datos.** Usa el catálogo público de temporada (todas sus páginas), así que no necesita cuenta.
- **Caché.** Se guarda en el teléfono: se ve sin conexión y no se vuelve a pedir durante 6 horas.

## 3. Dependencia de YomaShi respecto a tv.yoma.site

**Situación.** El puente de MyAnimeList (`yomashi-api.php` y `yomashi-connect.php`) es de toda Yoma, pero vive en el hosting de YomaTV. Si tv.yoma.site falla (certificado, verificación del hosting, cuota), YomaShi también pierde MAL.

**Hecho en la 3.2.19.** La app ya no localiza ese puente con la dirección de YomaTV:

- tiene su propia configuración, `YomaServices` (Dart) y `YomaServices` (Kotlin), que hoy apunta a tv.yoma.site;
- una prueba comprueba que Dart y Android coinciden.

Mudarlo es cambiar un valor en cada uno.

**Pasos para mudarlo a `api.yoma.site`** (cuando se decida):

1. Crear el subdominio `api.yoma.site` en InfinityFree, con SSL. El certificado intermedio ya va en la app para todo `*.yoma.site`.
2. Subir con `tools/deploy_anime_backend.py --remote-dir /api.yoma.site/htdocs --connect`:
   - los archivos de `server/`;
   - `private/config.local.php`, que usa la misma base de datos, así que las sesiones siguen valiendo.
3. En `server/private/yomashi-mal.php`, cambiar `YS_ORIGIN` y la dirección de retorno.
4. Añadir `https://api.yoma.site/mal-callback.php` en la aplicación de MyAnimeList.
5. Cambiar `YomaServices.host` en `lib/config/yoma_web.dart` y en `YomaWeb.kt`, y publicar la app.
6. Mantener el puente en tv.yoma.site hasta que no quede ninguna versión antigua de la app en uso.

**Riesgo a vigilar.** MyAnimeList permite una sola dirección de retorno por aplicación. Si no admite dos, el cambio debe hacerse a la vez que se publica la app.

## 4. Estructura propuesta

```
yoma.site       Portal: presentación, descarga de la app (GitHub Releases), enlaces.
tv.yoma.site    YomaTV web: catálogo, reproductor, cuenta web, radio, cola para PC.
shi.yoma.site   YomaShi: presentación (más adelante, lector web si se quiere).
api.yoma.site   Servicios compartidos: puente de MyAnimeList y, si se hace, la
                sincronización de la sección 1 (opción 2).
```

**En el repositorio:**

```
lib/, android/        App (YomaShi + YomaTV).
lib/design/           Tokens de diseño: fuente única para app y web.
server/               Código fuente de los servicios compartidos (puente MAL).
web/<dominio>/        Lo que se sube a cada htdocs (ver web/README.md).
tools/                Generación de tokens, despliegue, publicación del APK.
docs/arquitectura/    Fases 1, 2 y 3.
```

**Hecho en la 3.2.19.**

- El código de tv.yoma.site está en `web/tv.yoma.site/`: 211 archivos, sin credenciales ni datos generados.
- Una prueba comprueba que la versión publicada coincide con sus huellas (`ready.json`) y que no se cuela ningún `.local.php`.
- `.gitignore` impide subir credenciales y datos del servidor.

## Pendiente

- Elegir entre las opciones de la sección 1.
- Mover los servicios a `api.yoma.site` (sección 3), cuando se decida.
- Estadísticas de YomaTV en la app (sección 2, propuesta pequeña).
- Lo que sigue abierto de fases anteriores:
  - dividir `reader_screen.dart`;
  - revisar las reglas de exclusión, cuyas 11 pruebas siguen fallando.
