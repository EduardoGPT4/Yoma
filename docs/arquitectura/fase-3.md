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

**Hecho en la 3.2.21: los servicios compartidos están en `api.yoma.site`.**

| Pieza | Dónde | Por qué |
|---|---|---|
| API del puente de MAL y sincronización (`yomashi-api.php`) | **api.yoma.site** | Ya no depende del hosting web de YomaTV |
| Autorización en el navegador (`yomashi-connect.php` → MAL → `mal-callback.php`) | tv.yoma.site | Es la dirección de retorno registrada en la aplicación de MAL, y la web la usa para su propia conexión |
| Base de datos y configuración de MAL | Compartidas | api.yoma.site usa el mismo `private/config.local.php` |

**El sitio (`web/api.yoma.site`):**

- **Arranque propio y mínimo** (`private/app.php`): base de datos, límite de peticiones y errores, sin sesiones web ni migraciones; el esquema lo mantiene la web en la base compartida.
- **Copias exactas** del puente (`server/`) y de `mal-http.php` de la web. `test/backend/test_api_site.py` comprueba que no se separen y prueba el sitio de punta a punta con PHP y un MAL simulado, incluida la renovación de tokens.
- **`ping`:** solo responde bien si la base de datos funciona.

**La app** (`YomaServices`, en Dart y Kotlin):

- Usa api.yoma.site si responde a `ping`; si no, el mismo puente en tv.yoma.site.
- Vuelve a probar api cada 30 minutos o tras un fallo de red.
- Un api sin SSL o sin configuración nunca desconecta la cuenta: la app sigue con tv.

**Para activarlo:**

1. Activa el SSL gratuito de `api.yoma.site` en el panel de InfinityFree y espera a que se emita. Hoy sirve un certificado provisional autofirmado.
2. Sube `dist/sitios/api.yoma.site.zip` a `api.yoma.site/htdocs`.
3. Copia `tv.yoma.site/htdocs/private/config.local.php` a `api.yoma.site/htdocs/private/config.local.php`, con el gestor de archivos.
4. Abre `https://api.yoma.site/`: debe mostrar `{"service":"yoma-api","ok":true}`.
5. La app pasará sola a api.yoma.site en la siguiente comprobación: al abrirla o, como mucho, en 30 minutos.

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
