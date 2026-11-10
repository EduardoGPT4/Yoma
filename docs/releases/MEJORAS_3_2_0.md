# Yoma 3.2.0

## Nueva carpeta Yoma

Todo lo que Yoma guarda en el teléfono queda reunido en una sola carpeta en la raíz:

```
Yoma/
├─ YomaShi/
│  ├─ Manga/<manga>/<capítulo>/<páginas>
│  └─ Backups/
└─ YomaTV/
   └─ Anime/<anime>/Episodio 01 [SUB].mp4
```

- Al abrir esta versión, la carpeta anterior `YomaShi` se mueve a `Yoma/YomaShi` (en el mismo almacenamiento, sin copiar) y se actualizan las rutas guardadas: progreso, capítulos leídos, favoritos, categorías, cola de descargas, carpetas de la biblioteca y ajustes. Si algo ya existe en el destino, se conserva y no se sobrescribe.
- Los episodios de YomaTV dejan la carpeta privada de la app y pasan a `Yoma/YomaTV/Anime/<anime>/`. Se mueven en segundo plano cuando no hay descargas activas; mientras tanto se siguen reproduciendo desde su ubicación anterior.
- La migración solo se hace con el acceso a todos los archivos concedido y con la cola de descargas de manga detenida; si no se dan esas condiciones, se completa en el siguiente arranque. Si se interrumpe, el siguiente arranque termina de actualizar las rutas.
- Las carpetas llevan `.nomedia` para que páginas y episodios no llenen la galería.

## Permisos al abrir Yoma

- Nueva pantalla «Permisos de Yoma» con el acceso a todos los archivos (necesario para descargar) y las notificaciones (progreso de descargas), con «Permitir todo».
- Se basa en el estado real de cada permiso, no en una marca guardada. Antes, al reinstalar, Android restauraba la marca desde la copia de Google pero no el permiso, y las descargas fallaban con «No se pudo acceder al almacenamiento».
- El acceso a archivos se vuelve a pedir en cada arranque mientras falte; las notificaciones, una sola vez.
- La pantalla se actualiza sola al volver de los ajustes de Android.

## Descargas de YomaTV agrupadas por anime

- La pestaña Descargas muestra una tarjeta por anime con sus episodios en orden, el total descargado y el progreso de los que están en curso. Se despliega o pliega al tocarla.
