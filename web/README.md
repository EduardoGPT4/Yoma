# Web de Yoma

Cada carpeta es lo que se sube a la carpeta `htdocs` de su dominio en el hosting.

| Carpeta | Dominio | Qué es |
|---|---|---|
| `yoma.site/` | yoma.site | Página principal: presentación y descarga de la app |
| `shi.yoma.site/` | shi.yoma.site | Presentación de YomaShi |
| `tv.yoma.site/` | tv.yoma.site | YomaTV web (PHP y JS) y la autorización de MyAnimeList (dirección de retorno registrada) |
| `api.yoma.site/` | api.yoma.site | Servicios compartidos: puente de MyAnimeList y sincronización (copias de `server/`; necesita el `config.local.php` de tv) |

## No está en el repositorio

- **Credenciales:** `private/config.local.php` y `private/access.local.php`. Solo están en el servidor; la plantilla es `private/config.example.php`.
- **Datos que genera el servidor:** `data/`, `feeds/`, `downloads/` y lo mismo dentro de cada versión.
- **Versiones anteriores de tv.yoma.site:** se conservan en el hosting para volver atrás.

## Subir cambios

`tools/web_release.py` compara la carpeta con el sitio real y arma solo lo que falta:

```
python -I tools/web_release.py estado    tv.yoma.site
python -I tools/web_release.py paquete   tv.yoma.site
python -I tools/web_release.py publicado tv.yoma.site
```

1. **paquete** crea `dist/sitios/actualizacion/<sitio>-<commit>.zip`. Antes comprueba que `ready.json` esté al día.
2. Descomprime el zip en `htdocs` del sitio. Si el script lista archivos borrados, puedes eliminarlos del servidor.
3. **publicado** comprueba el sitio real (salud, estado y archivos). Si todo responde, anota el commit en `web/desplegado.json`; haz commit de ese archivo.

Los archivos de texto públicos se comparan descargándolos; los finales de línea no cuentan como cambio. El resto (PHP, `.htaccess`, `private/`, imágenes y fuentes) se compara con el último commit publicado. Nunca incluye `*.local.php` ni `data/`, `feeds/` o `downloads/`.

## tv.yoma.site por versiones

- **Versión activa:** `private/current.json` indica qué carpeta de `releases/` está activa.
- **Huellas:** `releases/<versión>/private/ready.json` guarda las huellas de sus archivos. Si cambias uno, actualízala; si no, `test/unit/yoma_web_source_test.dart` falla.
- **Puente de MyAnimeList:** su código fuente está en `server/` y se publica con `tools/deploy_anime_backend.py`.

## Colores y radios

Los toma de `lib/design/yoma_tokens.dart`. Después de cambiar un token:

```
python -I tools/generate_web_tokens.py
```

`test/unit/yoma_web_tokens_test.dart` comprueba que la web y la app no se separen.

## Mantenimiento del catálogo

InfinityFree no tiene cron. La tarea de GitHub «Mantenimiento del catálogo» (`.github/workflows/catalog-maintenance.yml`) llama a `maintenance.php` a los minutos 7 y 37 de cada hora, y hace hasta 30 trabajos por vez (GitHub a veces las retrasa). Los trabajos son: revisar el horario (cada 12 horas), leer listados de capítulos pendientes o con más de 30 días, y recorrer el directorio (cada semana). Usa `tools/run_catalog_maintenance.py`, que resuelve la comprobación del alojamiento.

Para activarla:

1. En el servidor, añade `'external_maintenance' => true,` a `releases/<versión>/private/config.local.php`.
2. En la web, entra con la cuenta administradora y abre el menú (☰) → **Preferencias**. Al final está el panel **Actualización del sitio**. Pulsa **Configurar actualización externa** y genera el token. Si el botón dice «Acerca de la actualización externa», el paso 1 no está hecho. Generar otro token invalida el anterior.
3. Guárdalo como secreto `YOMA_MAINTENANCE_TOKEN` del repositorio:

   ```
   gh secret set YOMA_MAINTENANCE_TOKEN --repo EduardoGPT4/Yoma
   ```

Sin el secreto, la tarea termina sin hacer nada. Para lanzarla a mano: pestaña **Actions** → «Mantenimiento del catálogo» → **Run workflow**.
