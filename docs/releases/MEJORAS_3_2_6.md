# Yoma 3.2.6

Resultado de una auditoría funcional de YomaTV y de su integración con MyAnimeList. No añade funciones: corrige fallos de sincronización, de reanudación y de avisos.

## Sincronización con MyAnimeList

- **Un envío solo cuenta si MAL lo confirma.** Antes cualquier respuesta sin error se daba por guardada y el episodio salía de la cola. Ahora la respuesta debe confirmar ese mismo anime con ese mismo número; si no, el episodio sigue pendiente y se reintenta.
- **Los fallos de sincronización ya se ven.** El aviso existía pero no se mostraba en ninguna pantalla. Ahora aparece en «Más → Mi lista de anime MAL» y en la pantalla de MyAnimeList, con un botón para sincronizar.
- **Sin conexión y sin nada pendiente no hay error.** Cada sincronización consultaba al servidor aunque no hubiera episodios que enviar, y sin internet eso se registraba como fallo. Ahora no se hace ninguna petición si la cola está vacía, y la comprobación de la extensión de anime se hace una vez por sesión.
- **Desmarcar un episodio lo retira de la cola.** Si se marcaba un episodio por error y se desmarcaba antes de enviarse, se subía igualmente a MAL. Ahora el pendiente baja al episodio visto más alto que queda. Lo que MAL ya confirmó no se reduce.
- **La sección de MyAnimeList se actualiza al momento.** Tras ver un episodio, «Viendo en MyAnimeList» seguía mostrando el número anterior hasta 12 horas y un anime de «Por ver» no pasaba a «Viendo». Ahora se refleja en cuanto MAL confirma, sin volver a descargar las listas.
- **Listas largas completas.** La lectura por páginas se guiaba por el número de filas recibidas en vez de por la continuación que indica el servidor. Ahora sigue esa continuación y rechaza respuestas sin lista en lugar de tomarlas por una lista vacía.
- **Un fallo de YomaTV con un título no oculta toda tu lista.** Si una sola búsqueda fallaba, la sección entera no aparecía. Ahora se muestra lo encontrado y lo que faltó se reintenta a los pocos minutos; si YomaTV no responde, se deja de buscar tras unos fallos.
- Tras resolver un conflicto se registra el número realmente enviado, no el anterior.

## Reproducción y navegación

- **«Reproducir» continúa por donde toca.** Tras terminar un episodio, el botón de la ficha volvía a abrir ese mismo episodio. Ahora abre el siguiente que falta por ver.
- **«Continuar viendo» sin episodios antiguos.** Si quedaba un episodio a medias y después se terminaba otro del mismo anime, reaparecía el antiguo. Ahora solo cuenta lo último que se abrió de cada anime.
- **Episodios nuevos sin reiniciar.** La ficha de un anime se pedía una vez por sesión; con la app abierta durante días no aparecían los episodios nuevos. Ahora se actualiza en segundo plano pasados 10 minutos.
- En pausa el reproductor ya no reescribe el progreso cada 5 segundos ni reordena el historial.
- Los errores del reproductor y de las descargas muestran su mensaje, no el texto técnico «PlatformException(…)».

## Servidor

- La página de autorización decía «No se cambiará tu lista de anime», que dejó de ser cierto desde que YomaTV sincroniza episodios. El texto está corregido en `server/yomashi-connect.php`; hay que subir ese archivo al alojamiento para que se vea.

## Pruebas

36 pruebas nuevas con servidores simulados: confirmación de escritura, sesión caducada (401), límite de peticiones (429), errores 5xx, respuestas no válidas, cambio de cuenta, paginación, cola sin conexión, desmarcado, copia de la lista, reanudación y avisos. Ninguna escribe en una cuenta real de MyAnimeList.
