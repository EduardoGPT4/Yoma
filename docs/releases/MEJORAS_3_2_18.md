# Yoma 3.2.18

## Fase 2: una sola YomaTV

- **Código retirado.** Se retiró la antigua YomaTV nativa de la cuenta web: sus pantallas, su reproductor, su panel de descargas y su envío de lo visto a tv.yoma.site. Desde la 3.2.17 todo eso lo hacen las pantallas de la app, así que no cambia nada de lo que ves.
- **Versiones anteriores.** Lo que esas versiones dejaron programado termina sin hacer nada.
- **Tamaño.** El APK pesa unos 450 KB menos.

## MyAnimeList

Lo visto en YomaTV sin conexión llega ahora a MyAnimeList igual que lo leído en YomaShi:

- al volver a la app, aunque estés en YomaShi;
- en el mantenimiento en segundo plano, con la app cerrada.

## Código más ordenado

- **YomaTV.** Cada pestaña (Inicio, Explorar, Biblioteca, Descargas y Más) está en su propio archivo.
- **Pantallas online de YomaShi.** Sus piezas están en archivos aparte.
- **Web.** Las tres páginas (yoma.site, tv.yoma.site y shi.yoma.site) toman sus colores y radios de los mismos tokens que la app, generados desde `lib/design/yoma_tokens.dart`.

Detalle en `docs/arquitectura/fase-2.md`.
