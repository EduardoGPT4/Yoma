# Yoma 3.2.30

## YomaShi

- **Ya no se abre el mismo capítulo varias veces:** en «Continuar leyendo» de Inicio y en el Historial, tocar de nuevo mientras carga abría un lector por cada toque, y luego había que salir varias veces.
  - Ahora se ve que está cargando y los toques repetidos no hacen nada.
- **El progreso de lectura ya no se pierde a veces:** si coincidía con una descarga en segundo plano, la base de datos podía estar ocupada y el progreso no se guardaba. Ahora espera y lo vuelve a intentar.
  - Lo mismo vale para favoritos, capítulos leídos y ajustes.

## YomaTV

- **Un doble toque en un episodio descargado ya no abre dos reproductores.**
- **Mensajes claros sin conexión:** el aviso de YomaTV ya no muestra texto técnico como «SocketException: Failed host lookup…».
  - También al abrir un episodio o vincular con MyAnimeList.

## Ambos

- Los mensajes de error llevan sus tildes: «Sin conexión a internet», «La conexión tardó demasiado», «Inténtalo de nuevo»…
- Al importar en Perfil o elegir una imagen, los errores también se explican con un mensaje claro.
- Componentes internos actualizados a sus últimas versiones compatibles.
