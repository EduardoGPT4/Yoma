# Pruebas en teléfono — 20 de octubre de 2026

Dispositivo: POCO X6 Pro 5G, Android 16 (API 36). APK de desarrollo 2.1.0+2. El APK inicialmente instalado coincidía por SHA-256 con el compilado tras la auditoría.

## Resultados observados

| Comprobación | Resultado |
| --- | --- |
| InManga | Recarga de catálogo, ficha de One Piece y resolución de páginas correctas. Una imagen del capítulo reciente se descargó correctamente (332.544 bytes). La imagen inicial del capítulo 01 devolvió HTTP 404; el lector oficial publica exactamente esa misma URL. |
| MangaDex | Catálogo, ficha parcial de OUT, imágenes del lector y descarga real correctos. |
| zonatmo.org | Catálogo, ficha y lectura de Yu☆Gi☆Oh! Zexal correctos; 30 páginas resueltas y primeras imágenes cargadas. |
| zonatmo.to | Catálogo, ficha parcial y lectura de SPY x FAMILY correctos; siete páginas resueltas y primeras imágenes cargadas. |
| Pausa | Trabajo de OUT detenido en 28/29 páginas. Dos muestras separadas mantuvieron 18.483.747 bytes. La pausa seguía conservada varias horas después. |
| Reanudación e integridad | OUT, capítulos 2 y 3, terminaron con 29 y 26 páginas confirmadas y archivadas, respectivamente. |
| Pantalla apagada | Con el dispositivo en estado Dozing, el capítulo 3 avanzó de 6 páginas/4.367.291 bytes a 10 páginas/7.139.611 bytes durante veinte segundos. Servicio en primer plano y bloqueo parcial de CPU activos durante la transferencia. |
| Fin de servicio | Tras terminar ambos trabajos, el servicio y su bloqueo de CPU dejaron de aparecer activos. |
| Archivos locales | Offline abrió el capítulo 2 desde su carpeta local: 29 rutas locales, imágenes cargadas y avance a la segunda página sin error. No se desactivó globalmente la conectividad del teléfono. |
| Rotación | En SPY x FAMILY, la página 2 se conservó al pasar a horizontal. Se restauró la orientación libre al acabar. |

Se restauró el límite de velocidad original (sin límite). Los trabajos anteriores, uno detenido y otro fallido, conservaron esos estados. Los capítulos descargados durante la prueba permanecen disponibles en Offline.

## Correcciones surgidas de la prueba

- Tarjetas: se observó un desbordamiento inferior de 5,6 píxeles con títulos de dos líneas. La cuadrícula y el carrusel ahora reservan la altura real de dos líneas, según densidad y escala de texto. Se comprobó en el teléfono y se añadieron ocho casos de regresión.
- Cola: se mostraban velocidad y tiempo restante obsoletos en trabajos pausados/fallidos. Ahora esos indicadores se muestran solamente durante la descarga.
- Lector: el fallo de imagen ocultaba la causa. Ahora muestra el mensaje correspondiente al error, conserva el reintento y permite avanzar de página. El visor continuo también transmite la causa del fallo.
- zonatmo.to: los géneros aparecían como números internos y la sinopsis mostraba entidades HTML. Se resuelven los nombres con la taxonomía pública, compartida durante la sesión; los IDs desconocidos se omiten. Los caracteres HTML se decodifican.

## Validación y límites

Tras las correcciones: 78 pruebas aprobadas, análisis Flutter sin incidencias, formato verificado y APK Android compilado. Las pruebas automatizadas de fuentes siguen usando un servidor local; las comprobaciones anteriores sí usaron la conexión del teléfono y los sitios reales.

El APK actualizado se instaló con conservación de datos y volvió a arrancar correctamente. Se confirmó la coincidencia SHA-256 entre el archivo compilado y el instalado: `bd2d0c6f10194d22451a8188f4a5ccd022860283ec825904e10f4bb82a49eb40`. Continúa mostrando la versión 2.1.0+2. En la ficha real de SPY x FAMILY se verificaron los nombres Acción, Comedia, Drama y Romance y la sinopsis decodificada. Se restauró InManga como fuente activa.

Estas muestras no certifican todos los capítulos de cada fuente ni la continuidad durante horas bajo cualquier política de batería. La imagen antigua de InManga con 404 depende del servidor de origen. No se validó iOS, agotamiento real del almacenamiento ni el timeout máximo de Android.
