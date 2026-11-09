# YomaShi 2.5.0

Implementación de las diez propuestas de experiencia de usuario.

1. **Biblioteca unificada.** Reúne carpetas, favoritos online y lecturas recientes con filtros Todos/Descargados/Favoritos/Leyendo, búsqueda y categorías. Conserva el gestor anterior de archivos desde el icono de carpeta. Las referencias canónicas y los vínculos de origen conocidos permiten unir descargas y favoritos; no se mezclan obras por tener el mismo nombre. Guardar en biblioteca utiliza los favoritos existentes, sin migrarlos ni descargar páginas.
2. **Continuar leyendo destacado.** Primera lectura con portada, capítulo, página, fecha y botón Continuar; otras recientes en carrusel. La biblioteca reúne las fuentes. Se elimina el porcentaje inventado cuando no se conoce el total de páginas.
3. **Estado en portadas.** Novedades comprobadas de favoritos, disponibilidad descargada, progreso leído y estado confirmado de MAL con icono y texto. La primera comprobación de novedades sigue estableciendo una base; no inventa capítulos nuevos. Los estados de MAL son la última consulta conocida.
4. **MyAnimeList transparente.** Ficha con obra e ID vinculados, capítulos, estado, consulta/envío reciente, pendientes y errores. Consulta explícita sin escribir en MAL; desde la ficha se revisa o corrige el vínculo. Las instantáneas se asocian a propietario y versión del vínculo, y se ocultan al cambiar de cuenta. No requieren cambios en el servidor.
5. **Fin de capítulo.** Tarjeta con siguiente título y disponibilidad offline, consulta de más capítulos en fuentes paginadas y estado al alcanzar el último disponible. Se mantiene el avance habitual por toque, botones o gesto.
6. **Navegación por páginas.** Miniatura con decodificación limitada y espera de 160 ms para evitar pedir cada página cruzada al arrastrar. Solo se cambia de página al soltar. Los saltos grandes ofrecen volver a la posición anterior; la acción deja de aplicarse al cambiar de capítulo.
7. **Descargas accesibles.** Contador en navegación, resumen de la tarea activa o pendiente y hoja con progreso, motivo de espera, pausa y reanudación desde otras pestañas. Reutiliza el motor nativo existente.
8. **Perfil y ajustes.** Perfil centrado en identidad, cuenta e historial/resumen; configuración en una ruta propia con búsqueda por grupos y sin perder importación, exportación, almacenamiento, automatización ni apariencia.
9. **Identidad visual.** Superficies y radios coherentes, menos sombras, encabezados más ligeros y controles con área táctil estándar. Listas y hojas siguen desplazándose con texto ampliado.
10. **Ayuda contextual.** Bienvenida breve y consejos en biblioteca, ficha, descargas y controles del lector. Cada consejo puede cerrarse y no vuelve a aparecer tras reiniciar.

## Datos y límites

- Los favoritos online guardados y el progreso existente aparecen sin una importación nueva. Los archivos se conservan.
- La caché de estado de MAL no sustituye al progreso local ni modifica capítulos leídos al consultar. Las credenciales siguen cifradas.
- La biblioteca permite seguir una lectura online cuando el capítulo guardado no está entre los descargados. Si la fuente ya no lo ofrece, muestra un error y conserva el progreso.
- Un manga sin origen conocido sigue siendo local. Las categorías anteriores permanecen disponibles en el gestor de archivos y la vista unificada.
- La descarga final conserva el certificado personal y usa versión 2.5.0+9 (ARM64: 2009).

## Verificación

- Batería Flutter: 167 pruebas correctas; dos comprobaciones opcionales excluidas de la ejecución normal.
- Capturas de componentes con el tema real y fuentes Roboto en `build/verification/ui-2.5.0/`, generadas sin cuentas ni conexiones reales.
- Análisis estático sin incidencias.
- La prueba Android usa exclusivamente `app.yomashi.reader.qa`; nunca sustituye ni borra la instalación personal.

- Android API 35 en emulador, modo profile: descarga de ocho páginas, pausa/reanudación, reparación de una sola página, navegación y salto por miniaturas, tarjeta final, filtros de biblioteca, guardado sin descargar, búsqueda de ajustes, exportación/restauración y WorkManager con resultado SUCCEEDED. Informe: `build/integration_reports/ux-2.5.0.json`.
- La entrada de texto de la prueba registra el cliente de teclado simulado en modo profile; verifica también que el campo recibió el texto antes de comprobar el filtro.
