# YomaShi 2.8.0

## Mangas MAL

Con una cuenta de MyAnimeList vinculada, Inicio muestra **Mangas MAL** a la derecha del selector de fuentes. El botón desaparece al desconectar la cuenta. La sección consulta únicamente **Reading / Leyendo** y **Plan to read / Por leer** de esa cuenta, con portadas, capítulos leídos, filtros, actualización y «Cargar más mangas». Los demás estados no se muestran.

Cada manga abre una búsqueda independiente en MangaDex, InManga, Lectortmo, zonatmo.to y ManhwaWeb, según los conectores disponibles. Los resultados exigen el título completo o un nombre alternativo proporcionado por MAL: se ignoran diferencias de mayúsculas, acentos latinos, puntuación y entidades HTML, conservando números y caracteres de otros alfabetos. No se usa similitud ni se aceptan secuelas por compartir un prefijo. Las preferencias de idioma de cada fuente siguen aplicándose.

La comparación conserva el título original del catálogo antes de la limpieza visual existente. Así, aunque una portada muestre «Obra» después de limpiar «Obra - 2», la búsqueda exacta sigue distinguiendo ambas obras. El dato original también se conserva al serializar o asignar la fuente de un resultado.

Cada fuente tiene indicador de carga, resultados, aviso sin coincidencias y reintento de errores. Elegir un resultado abre su ficha en la fuente correspondiente sin cambiar la fuente activa de Inicio. Consultar estas pantallas no escribe estados en MAL ni vincula automáticamente el progreso de lectura: ese vínculo sigue siendo una acción explícita en la ficha.

## Implementación y límites

- El servidor consulta el endpoint oficial `/v2/users/@me/mangalist` con OAuth, estado, límite y desplazamiento validados. No acepta nombres de otras cuentas ni sigue URLs de paginación del proveedor.
- Las dos listas se paginan por separado, deduplicando IDs y conservando la lista disponible si falla la otra.
- Las credenciales y el propietario se comprueban antes y después de cada consulta. Una desconexión o cambio de cuenta descarta respuestas anteriores y oculta la lista y las coincidencias de esa sesión.
- Las búsquedas se ejecutan en paralelo entre fuentes. Para limitar la red, cada fuente prueba hasta cuatro títulos y dos páginas por título, deteniéndose al encontrar coincidencias exactas. Un título traducido que MAL no declare, o un resultado más allá de ese límite, puede no aparecer.
- Las fuentes pueden requerir resolver su protección web desde la app o estar temporalmente fuera de servicio. La biblioteca MAL requiere conexión y no se persiste entre cuentas.
- No hay cambios en la configuración de exclusiones, el apartado separado adicional, los mangas descargados ni las credenciales existentes.

## Verificación

Las 24 pruebas nuevas de Flutter pasan: listas y paginación, estados permitidos, títulos y alias, conservación del título original del catálogo, cancelación, aislamiento de cuentas, errores independientes y navegación. Las pantallas se revisaron con capturas, texto grande y un ancho de 320 píxeles. El análisis estático no encuentra incidencias.

La batería completa obtiene **231 pruebas correctas, 11 fallos existentes y tres pruebas opcionales omitidas**: dos consultas a servicios reales y una captura de interfaz. Los once fallos siguen relacionados con etiquetas ausentes en la configuración personalizada de exclusiones conservada por petición del usuario; no se eliminaron ni desactivaron las pruebas.

El contrato HTTP del servidor ejecuta ocho pruebas: **siete correctas y una prueba opcional de navegador omitida**. Usa PHP y un proveedor MAL local simulado, sin leer credenciales ni modificar cuentas reales. También se comprueba que instalar la extensión dos veces produce el mismo código y que únicamente cambian el módulo YomaShi y la ruta de lectura de manga en el adaptador MAL del alojamiento.

El backend se publicó como `yomashi-mal-library-20261105-1`, con copia de seguridad cifrada verificada y comprobación de salud correcta. La prueba pública crea y revoca su propia conexión pendiente: las consultas a los dos estados admitidos solicitan autorización (409), y los otros estados se rechazan antes de consultar MAL (422). No se accede a la cuenta del usuario para esa comprobación.

Se ejecutó además por separado la prueba opcional del cliente Dart contra ese servidor real: negociación de la cookie del alojamiento, creación de una conexión pendiente, solicitud de autorización y revocación del dispositivo. La prueba pasó, sin vincular ni modificar una cuenta MAL real.

La prueba con una cuenta MAL real en el teléfono queda pendiente; las pruebas automatizadas usan respuestas controladas.
