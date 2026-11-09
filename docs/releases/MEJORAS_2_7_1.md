# YomaShi 2.7.1

Entrega personal ARM64 a partir del proyecto `Expedition-9`.

- MangaDex con 42 idiomas seleccionables, búsqueda de idiomas y selección persistida.
- Traducción manual de imágenes en el lector online de Android, con regreso al original.
- Exclusiones centralizadas para el catálogo y el buscador, caché de IDs con concurrencia limitada y renovación de los catálogos cuando cambian las reglas.
- Documentación y pruebas organizadas por carpetas.
- Número de compilación incrementado para actualizar la instalación anterior.

Los APK y sus SHA-256 se publican en [GitHub Releases](https://github.com/EduardoGPT4/YomaShi/releases). No se guardan binarios ni claves de firma en Git.

El APK se comprueba mediante compilación release, pruebas locales, análisis estático y verificación de versión, arquitectura y certificado. Las comprobaciones de fuentes de esta entrega usan respuestas locales simuladas; la conexión a los sitios reales y el funcionamiento en el teléfono se validan por separado.

## Configuración y pruebas de esta entrega

Se conserva la lista actual de `ContentExclusions.tags`, con las dos entradas personalizadas, conforme a la preferencia indicada para esta entrega.

La batería local termina con **207 pruebas correctas, 11 fallos y una captura opcional omitida**. Los once fallos corresponden a comprobaciones de exclusiones que esperan etiquetas adicionales ausentes de la configuración actual. No se han eliminado ni desactivado esas pruebas. El análisis estático y el formato del proyecto terminan sin incidencias.
