# Pruebas

| Carpeta | Tipo de comprobaciones |
| --- | --- |
| `unit/` | Paginación, filtros, estados y mensajes de error. |
| `services/` | Servicios, persistencia, descargas, fuentes, traducción y puentes nativos con datos de prueba. |
| `widgets/` | Pantallas, controles, ajustes, perfil y composición visual. |
| `live/` | Pruebas opcionales que consultan servicios reales y requieren activación explícita. |
| `backend/` | Contratos HTTP del servidor MyAnimeList con PHP y respuestas locales controladas. |

Ejecuta los comandos desde la raíz del proyecto:

```shell
flutter analyze
flutter test test/unit test/services test/widgets
```

`flutter test` también descubre recursivamente las pruebas de estas carpetas. Las pruebas de `live/` y las capturas visuales se omiten salvo activación explícita.

Para la traducción y el lector:

```shell
flutter test test/services/page_translation_test.dart test/widgets/reader_ui_ux_test.dart test/widgets/reader_widget_regression_test.dart
```

Para los contratos del servidor:

```shell
python test/backend/test_myanimelist.py
```

Las [entradas de integración Android](../integration_test/) y su [controlador](../test_driver/integration_test.dart) mantienen sus ubicaciones originales. La herramienta `tools/verify_android.ps1` comprueba el identificador aislado `app.yomashi.reader.qa` antes de instalar su APK de pruebas.

[Volver al README principal](../README.md).
