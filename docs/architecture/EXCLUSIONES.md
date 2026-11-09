# Exclusiones de contenido

Las reglas se editan en un único sitio: [ContentExclusions.tags](../../lib/services/content_exclusions.dart). Se incluyeron `guro`, `ryona` y `snuff`, las protecciones de exclusión comprobadas por las pruebas y las dos entradas personalizadas anteriores, sin sus espacios finales.

Para añadir otra restricción, añade una entrada al conjunto `tags`:

```dart
'nueva etiqueta',
```

Escribe el nombre sin prefijos como `female:` o `male:`. El componente genera esas variantes automáticamente para los índices. El cambio entra en el siguiente APK compilado.

## Aplicación de las reglas

| Lugar | Comprobación |
| --- | --- |
| Catálogo | Se excluyen los IDs de los índices correspondientes y se revisan las etiquetas de cada resultado. |
| Fichas y páginas | Se comprueban las etiquetas incluso al abrir una referencia directamente. |
| Sugerencias | Se eliminan las entradas que coinciden con la lista central. |
| Texto escrito y consultas directas al servicio | Se impide enviar consultas que coincidan con las exclusiones. |

La coincidencia ignora mayúsculas, espacios, guiones y guiones bajos, y también reconoce nombres compuestos. Las decisiones se basan en los índices y metadatos declarados; este componente no clasifica el contenido de las imágenes.

`ExcludedContentIds`, en el mismo archivo, reúne los IDs sin duplicados, limita la carga a cuatro solicitudes simultáneas y conserva el resultado durante diez minutos. Las llamadas concurrentes comparten una carga pendiente. Al invalidar la caché, una carga anterior no puede reemplazar su resultado nuevo.

La clave de los catálogos guardados también incluye la lista de reglas. Al instalar una compilación con exclusiones distintas, los resultados guardados con la política anterior dejan de reutilizarse. Las claves de caché de las otras fuentes se conservan.

El adaptador de la fuente conserva únicamente la lectura de los índices. Un error de conexión o del servidor se propaga y permite reintentar; no se almacena como una lista de exclusiones completa. Los índices ausentes con HTTP 404 conservan el tratamiento existente del adaptador.

## Pruebas locales

```shell
flutter analyze
flutter test test/unit test/services test/widgets
```

Las pruebas específicas cubren las reglas adicionales, las variantes normalizadas, la exclusión por ID y por metadatos, las referencias directas, las consultas sin solicitudes de red, la caché, su caducidad, la concurrencia, la invalidación y la recuperación tras un error HTTP simulado. No requieren consultar el sitio real.

Validación del 3 de noviembre de 2026: **218 pruebas correctas, cero fallos y una captura opcional omitida**. El análisis completo terminó sin incidencias. Los registros locales están en `build/reports/content-exclusions/`. No se generó un APK nuevo.
