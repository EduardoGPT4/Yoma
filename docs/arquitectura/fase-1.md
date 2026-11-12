# Fase 1: compatibilidad y coherencia

Estado al 12 de noviembre de 2026 (Yoma 3.2.16).

## 1. Pruebas de bloqueo de contenido (11 fallos)

**Causa única.** Las 11 pruebas comprueban que el filtro de exclusión bloquea `loli`, `shota`, `guro`, `ryona` y `snuff`. El mecanismo funciona: normaliza mayúsculas, espacios y guiones, revisa etiquetas, sugerencias, búsquedas e índices. Lo que falla es la lista de reglas.

`lib/services/content_exclusions.dart` (`ContentExclusions.tags`) contiene solo dos palabras de relleno, `electroencefalografista` y `esternocleidomastoideo`, con el comentario «No cambies por nada del mundo esto». Está así desde el primer commit del repositorio (`4de3f08`, «Importa Yoma 3.0.2 tal como está en el equipo de desarrollo»). Por tanto, **la app no bloquea hoy ninguna de esas etiquetas** en la fuente Hitomi.

| Archivo | Pruebas que fallan |
|---|---|
| `test/services/content_exclusion_test.dart` | 3 |
| `test/services/hitomi_service_test.dart` | 4 |
| `test/unit/content_exclusions_test.dart` | 3 |
| `test/widgets/hitomi_tag_suggestions_test.dart` | 1 |

**Sin cambios.** No se modificaron las reglas ni las pruebas: requiere una revisión específica.

**Consecuencia.** `flutter test` termina con fallos, así que la integración continua (`.github/workflows/flutter.yml`) no puede estar en verde y esconde regresiones nuevas.

**Recomendación.** Restaurar las etiquetas que las pruebas esperan. Bloquear contenido sexual con menores (`loli`, `shota`) no es opcional.

## 2. Pantallas Kotlin antiguas abiertas desde la web integrada

La web de YomaTV dentro de la app (`AnimeScreen`, abierta desde «Más › YomaTV en la web») habla con Android mediante `NativeAnimeBridge`. Estas son sus salidas a pantallas Kotlin (`app.yomatv.mobile`):

| Entrada | Abre | Equivalente en Flutter | ¿Equivalente funcional? |
|---|---|---|---|
| Icono «Descargas de anime» de la barra | `MainActivity`, pestaña Descargas | Pestaña Descargas de YomaTV | No: muestra otra cola (ver abajo) |
| «↓ Descargar» y «Capítulos para llevar» (mensaje `plan`) | `MainActivity` con selector de capítulos | Descarga desde la ficha de Flutter | No: guarda en la cola de la cuenta web |
| Reproducir con MP4Upload (mensaje `play_online`) | `PlayerActivity` | `AnimePlayerScreen` | No: registra lo visto en la cuenta web y tiene imagen en imagen |
| Mensaje `more` | `MainActivity` | Pestaña «Más» | La web ya no lo envía: rama sin uso |
| Notificaciones de la cola web | `MainActivity`, Descargas | — | Igual que la primera fila |

**Por qué no se redirigieron a Flutter.** Hay dos modelos de datos:

- **Cuenta web (Kotlin).**
  - La cola de descargas pertenece al usuario de la web (`Prefs.owner`, el id de tv.yoma.site).
  - El plan lo resuelve el servidor (`offline_plan`).
  - Lo visto se envía a la web con `watch_scrobble`, que actualiza el historial web y MyAnimeList a través de la cuenta web.
- **Local (Flutter).**
  - La cola es local (`owner = 1`).
  - Las fuentes se resuelven en el teléfono.
  - Lo visto se guarda en `anime_progress` y se sincroniza con la sesión MAL de la app (`anime_mal_client`).

Redirigir esas entradas a Flutter cambiaría:

- adónde se registra lo visto: la cuenta web dejaría de recibirlo;
- qué cola aparece;
- y se perdería la imagen en imagen.

Esa decisión afecta a MAL y al historial de las dos plataformas, así que queda pendiente de aprobación. No se cambió ninguna ruta.

**Hecho en su lugar.** Las pantallas Kotlin ya no rompen la identidad visual: usan exactamente los colores de Yoma (sección 4).

### Opciones para unificar (pendiente de decisión)

1. **Flutter como única interfaz, con el modelo local.**
   - La web integrada envía `plan` y `play_online` a Flutter.
   - Las descargas de la cuenta web se migran a la cola local.
   - Lo visto deja de enviarse a la cuenta web; sigue llegando a MAL por la sesión de la app.
   - Hay que añadir imagen en imagen al reproductor de Flutter antes de retirar `PlayerActivity`.
2. **Flutter como única interfaz, conservando la cuenta web.**
   - El reproductor y la cola de Flutter aprenden a trabajar con la cuenta web: `offline_plan` y `watch_scrobble`.
   - Es más trabajo, pero el historial de la web y el de la app coinciden.
   - Encaja con la Fase 3, que busca compartir biblioteca e historial.
3. **Mantener Kotlin para la cuenta web**, ya con el mismo diseño, hasta la Fase 3.

## 3. Enlace de descarga de la web

tv.yoma.site ofrecía «YomaTV Android 1.4.0» (repositorio antiguo `EduardoGPT4/YomaTV`).

**Cambios en `dist/sitios/tv.yoma.site/releases/yoma-design-20261111-1/assets/`:**

- **`app-downloads.js`.**
  - Android se descarga desde `EduardoGPT4/Yoma` (`Yoma-<versión>-arm64.apk`).
  - Windows sigue en `EduardoGPT4/YomaTV`, porque es el descargador de PC.
  - Cada plataforma se actualiza por separado con la API de GitHub.
  - Los textos presentan Yoma (YomaTV y YomaShi).
- **`app-releases.json`:** la versión incluida es Yoma 3.2.16, con su tamaño y SHA-256.
- **`private/ready.json`:** huellas actualizadas.

## 4. Colores

**Web de YomaTV.** Los colores heredados de «Medianoche» pasan a los tokens de Yoma:

- **`mobile-app.css`**, la web dentro de la app, donde se veían el coral y los violetas antiguos. Ya no redefine `--bg`, `--surface`, `--text`, `--muted` ni `--accent`: usa los de `yoma.css`.
- **`comfort.css`:** valores de respaldo.
- **`medianoche.css`:** controles sobre el vídeo e insignias sobre portadas, que siguen siendo oscuros en ambos temas.

Lo que no cambia:

- el bloque de tokens inicial de `medianoche.css`, que `yoma.css` sustituye;
- las sombras y fondos neutros.

**Pantallas Kotlin.** `YomaColors.kt` reúne los colores de Yoma. Los nombres históricos (`INK`, `PAPER`, `ACCENT`…) apuntan a ellos y los errores usan el color de error. El tema `Theme.Yoma` usa el fondo #101014 y el acento #F0848D.

**Prueba:** `test/unit/yoma_kotlin_colors_test.dart` compara `YomaColors.kt` con `yoma_tokens.dart` y falla si vuelve a aparecer un color fijo en esas pantallas.

## Pendiente

- Decidir el modelo de datos de YomaTV (sección 2) antes de redirigir rutas o retirar Kotlin.
- Revisar y restaurar las reglas de exclusión (sección 1).
- Subir el código de tv.yoma.site al repositorio, sin `private/config.local.php`, para poder probar la web y versionarla.
- Fase 2: tokens de la web generados desde `yoma_tokens.dart` y un único nombre por color en los tres sitios.
