# Yoma 3.2.16

## Fase 1: un mismo aspecto en todo YomaTV

- **Pantallas nativas de YomaTV** (descargas de la cuenta web, «Más», selector de capítulos y reproductor de la web integrada):
  - usan ahora los colores de Yoma: fondo #101014, acento #F0848D y los mismos grises que el resto de la app;
  - sus títulos usan la letra de Yoma, sans en negrita, en lugar de una letra con serifa;
  - los errores de descarga usan el color de error de Yoma.
- **Colores centralizados:** están en `YomaColors.kt`. Una prueba comprueba que coinciden con `yoma_tokens.dart`.

## Web de YomaTV (paquete para subir)

- **Enlace de descarga:** la tarjeta para Android ofrece Yoma (YomaTV y YomaShi) en lugar de la app antigua YomaTV 1.4.0. El descargador de Windows no cambia.
- **Colores:** la web dentro de la app deja el coral y los violetas antiguos y usa los colores de Yoma.

## Documentación

`docs/arquitectura/fase-1.md` recoge:

- la causa de las 11 pruebas de bloqueo de contenido que fallan;
- las rutas que siguen abriendo pantallas Kotlin y la decisión pendiente sobre el modelo de datos de YomaTV.
