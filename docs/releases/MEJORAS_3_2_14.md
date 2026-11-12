# Yoma 3.2.14

## YomaTV vuelve a conectar con tv.yoma.site

YomaTV fallaba con `HandshakeException … CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`.

La causa está en el servidor: `tv.yoma.site`, `yoma.site` y `shi.yoma.site` solo envían su propio certificado, sin el certificado intermedio de Google Trust Services (WR1) que lo une a una raíz de confianza. Los navegadores lo completan por su cuenta; la app no.

Ahora la app incluye los certificados intermedios públicos de Google Trust Services (WR1–WR5 y WE1–WE4):

- en las conexiones de YomaTV y MyAnimeList hechas desde Dart;
- en la configuración de red de Android para `yoma.site` y sus subdominios, que usa la web de YomaTV dentro de la app.

La raíz de confianza sigue siendo la del sistema: los intermedios solo sirven para completar la cadena, no para aceptar certificados que no estén firmados por una raíz del sistema.

## Icono de la pestaña de YomaTV

La web de YomaTV usa ahora el logo de YomaTV de la app como icono de la pestaña y de la app instalada desde el navegador.
