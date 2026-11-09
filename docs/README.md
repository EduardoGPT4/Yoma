# Documentación de YomaShi

| Carpeta | Contenido |
| --- | --- |
| `architecture/` | [Arquitectura y flujos de datos](architecture/ESTRUCTURA.md) y [configuración de exclusiones](architecture/EXCLUSIONES.md). |
| `design/` | [Diseño visual y componentes](design/DISENO_VISUAL.md) y [recursos de marca](design/MARCA_YOMASHI.md). |
| `reader/` | [Traducción de imágenes online](reader/TRADUCCION_LECTOR.md). |
| `releases/` | Implementación del informe e historial de mejoras. |
| `testing/` | [Resultados de las pruebas en teléfono](testing/PRUEBAS_TELEFONO.md). |

## Historial de cambios

- [Versión 2.8: biblioteca MAL y coincidencias entre fuentes](releases/MEJORAS_2_8.md).
- [Versión 2.7.1: entrega personal y estado de las comprobaciones](releases/MEJORAS_2_7_1.md).
- [Implementación del informe original](releases/IMPLEMENTACION.md).
- [Versión 2.2: funciones y verificación](releases/MEJORAS_2_2.md).
- [Versión 2.3: MyAnimeList](releases/MEJORAS_2_3.md).
- [Versión 2.4: interfaz y accesibilidad](releases/MEJORAS_2_4.md).
- [Versión 2.5: biblioteca y lectura](releases/MEJORAS_2_5.md).

Los resultados y números de versión de estos documentos corresponden a sus comprobaciones históricas. La versión del código actual se declara en [pubspec.yaml](../pubspec.yaml).

## Carpetas del proyecto

```text
lib/                  Código Dart: datos, modelos, proveedores, pantallas,
                      servicios, utilidades y widgets.
assets/               Recursos incluidos en la app.
android/              Proyecto nativo Android y configuración de firma.
ios/, linux/, macos/,
web/, windows/        Proyectos de las otras plataformas de Flutter.
server/               Puente de MyAnimeList.
docs/                 Documentación por área e historial de versiones.
test/                 Pruebas agrupadas por tipo y pruebas del servidor.
integration_test/     Entradas de las pruebas Android en un paquete de QA.
test_driver/          Controlador e informes de las pruebas Android.
tools/                Herramientas de mantenimiento y publicación.
build/reports/        Registros y archivos históricos de diagnóstico locales.
```

Las carpetas de plataformas y las entradas Android conservan las rutas que utilizan Flutter, Gradle y el [workflow de validación](../.github/workflows/flutter.yml). [Organización de las pruebas](../test/README.md).

## Archivos generados y registros locales

`build/` y `.dart_tool/` contienen salidas y cachés de las herramientas. Los APK conservan sus rutas en `build/app/outputs/flutter-apk/`; los binarios se entregan a través de GitHub Releases.

Los archivos históricos que antes estaban sueltos en `build/` se agrupan en:

- `build/reports/logs/`: análisis, pruebas, compilaciones, emuladores y despliegues.
- `build/reports/apk/`: inspecciones de metadatos y registros de plugins.
- `build/reports/releases/`: notas de entregas anteriores.
- `build/reports/metadata/`: inventarios y metadatos de diagnóstico.
- `build/reports/patches/`: parches conservados.
- `build/reports/snapshots/`: copias anteriores de archivos de trabajo.
- `build/reports/helpers/`: utilidades temporales usadas en diagnósticos anteriores.
- `build/reports/organization/`: inventario de movimientos y verificación de integridad de esta reorganización.

Estos registros son locales y permanecen excluidos de Git. Los archivos locales de herramientas y del IDE siguen excluidos mediante [.gitignore](../.gitignore).

## Verificación de la reorganización

Se reubicaron 9 documentos, 33 pruebas y 106 archivos históricos de diagnóstico. Se actualizaron los enlaces, los comandos documentados y tres imports entre pruebas.

El inventario local `build/reports/organization/manifest.json` conserva las rutas anteriores, las nuevas y sus SHA-256. La verificación confirmó el contenido de 19 archivos relacionados con Hitomi, los 14 APK existentes y los 30 enlaces locales de la documentación.

El análisis terminó sin errores y con dos advertencias en `test/services/hitomi_service_test.dart`. Las pruebas locales terminaron con 185 correctas, una omitida y seis fallos en comprobaciones de exclusión de contenido y Hitomi con la configuración conservada. Durante esa reorganización, el código de la app y el contenido de sus pruebas de Hitomi conservaron los hashes anteriores. Las pruebas `live/` no se ejecutaron.

Los registros completos están en `build/reports/organization/flutter-analyze-final.log` y `build/reports/organization/flutter-tests-final.log`.

Tras separar el [sistema de exclusiones](architecture/EXCLUSIONES.md), la validación local del 3 de noviembre de 2026 terminó con 218 pruebas correctas, cero fallos, una captura opcional omitida y análisis completo sin incidencias. Los registros de esa comprobación están en `build/reports/content-exclusions/`.

[Volver al README principal](../README.md).
