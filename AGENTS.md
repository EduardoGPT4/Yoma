\# Instrucciones de trabajo



\## Objetivo principal



Completa las tareas solicitadas de principio a fin. Prioriza trabajar y entregar resultados funcionales sobre explicar lo que planeas hacer.



\## Forma de actuar



\- Examina el proyecto antes de modificarlo.

\- Deduce la intención usando el código, archivos y contexto disponibles.

\- Toma decisiones razonables por tu cuenta cuando falten detalles menores.

\- Pregunta solamente cuando falte información indispensable o haya varias opciones con consecuencias importantes.

\- No detengas el trabajo para pedir confirmación sobre decisiones reversibles.

\- Corrige errores directamente relacionados con la tarea. Si detectas problemas ajenos a su alcance, evita ampliar innecesariamente los cambios, salvo que impidan completarla.

\- No abandones una tarea después de implementar solo una parte.



\## Implementación



\- Conserva la estructura y el estilo existentes.

\- Busca primero si ya existe una función, componente o patrón reutilizable.

\- Evita cambios innecesarios y dependencias nuevas sin una razón concreta.

\- Considera casos límite y posibles efectos en otras partes del sistema.

\- No inventes archivos, APIs, resultados ni comportamientos que no hayas comprobado.



\## Verificación



\- Revisa los archivos modificados.

\- Ejecuta las pruebas, compilación o análisis disponibles.

\- Si una comprobación falla, investiga y corrige la causa.

\- No afirmes que algo funciona si no pudiste verificarlo.

\- Detente cuando la tarea esté completa y suficientemente comprobada.


\## Depuración y diagnóstico de errores


## Depuración y diagnóstico de errores

- Antes de corregir un error, investiga su causa raíz. No modifiques código basándote únicamente en suposiciones.
- Intenta reproducir el problema mediante pruebas, ejecución, registros o análisis estático, según las herramientas disponibles.
- Examina primero los mensajes de error, stack traces, logs y componentes relacionados.
- Formula hipótesis concretas y contrástalas con evidencias antes de implementar una solución.
- Distingue entre la causa raíz del problema y sus síntomas. Prioriza resolver la causa raíz.
- Evita soluciones temporales, excepciones silenciadas y mecanismos que oculten errores sin resolverlos.
- No elimines funcionalidades ni desactives validaciones o pruebas para conseguir que una compilación termine correctamente.
- Prioriza correcciones pequeñas y localizadas que respeten la arquitectura existente.
- Si un primer intento falla, analiza el resultado antes de probar otra solución. No repitas cambios equivalentes sin nueva evidencia.
- Cuando sea viable, crea una prueba que reproduzca el fallo antes de corregirlo y comprueba que pasa después.
- Después de cada corrección, verifica tanto el comportamiento afectado como las funcionalidades relacionadas para detectar regresiones.
- Si el error depende de servicios externos, permisos, credenciales o condiciones del entorno, identifica claramente esa dependencia.
- Si no puedes reproducir o verificar un error, utiliza la evidencia disponible, aplica únicamente cambios justificados y declara la limitación.
- No declares resuelto un problema basándote únicamente en que el código compila.

### Diagnóstico de aplicaciones Android

- Utiliza Android Logcat, excepciones y stack traces cuando estén disponibles.
- Investiga problemas relacionados con el ciclo de vida de actividades, fragmentos, navegación y conservación del estado.
- Comprueba los permisos, almacenamiento, conectividad y compatibilidad con las versiones de Android pertinentes.
- Ante errores de compilación, identifica la causa antes de modificar configuraciones de Gradle, SDK o dependencias.
- Ante errores de red, distingue entre problemas de conexión, respuestas HTTP, parsing, autenticación y cambios en servicios externos.
- Ante fallos de fuentes de manga, revisa por separado la búsqueda, obtención de metadatos, listado de capítulos y carga de imágenes.
- Evita que un error de una fuente externa provoque fallos innecesarios en otras fuentes o en toda la aplicación.
- Verifica que las correcciones no afecten las descargas, el lector, el historial ni la persistencia de datos.

### Criterios para considerar un error resuelto

- La causa raíz está identificada o existe una explicación sustentada en evidencias.
- La corrección aborda el problema identificado.
- Las pruebas pertinentes pasan, cuando pueden ejecutarse.
- No se detectaron regresiones en las funcionalidades relacionadas durante las verificaciones realizadas.
- Se documentan las comprobaciones que no pudieron realizarse y cualquier limitación pendiente.



\## Comunicación



\- Mantén las explicaciones breves y concretas.

\- Durante el trabajo, informa únicamente hallazgos o decisiones relevantes.

\- No describas cada comando ni repitas el contenido de la solicitud.

\- Al terminar, indica:

&#x20; 1. Qué cambiaste.

&#x20; 2. Cómo lo verificaste.

&#x20; 3. Qué limitación real queda, si existe.



\## Preferencias



\- Idioma de respuesta: español.

\- Código, nombres de variables y comentarios: sigue el idioma existente en el proyecto.

\- Evita tutoriales largos salvo que se soliciten.

\- Cuando el usuario reporte un problema, intenta corregirlo directamente.



\### Restricciones técnicas



\- No hay restricciones técnicas adicionales, pero conserva la compatibilidad, los datos del usuario, las credenciales y el sistema de firma y publicación existentes.

## Entrega de APK en GitHub

- Publica siempre cada APK final que entregues al usuario en las Releases de https://github.com/EduardoGPT4/YomaShi.
- Entrega el enlace de descarga de GitHub, además de cualquier archivo local. No guardes APK en el historial de Git.
- Usa el APK personal firmado con el certificado existente y verifica versión, firma y pruebas antes de publicarlo. Una firma nueva de un runner de CI no permite actualizar la instalación personal.
- Usa `tools/publish_apk.py` con el APK, sus notas y el commit de código que se compiló. El publicador conserva las credenciales en memoria y verifica tamaño y SHA-256 antes de publicar la Release.
