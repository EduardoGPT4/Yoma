# Web de Yoma

Cada carpeta es lo que se sube a la carpeta `htdocs` de su dominio en el hosting.

| Carpeta | Dominio | Qué es |
|---|---|---|
| `yoma.site/` | yoma.site | Página principal: presentación y descarga de la app |
| `shi.yoma.site/` | shi.yoma.site | Presentación de YomaShi |
| `tv.yoma.site/` | tv.yoma.site | YomaTV web (PHP y JS) y, por ahora, los servicios compartidos (puente de MyAnimeList) |

## No está en el repositorio

- **Credenciales:** `private/config.local.php` y `private/access.local.php`. Solo están en el servidor; la plantilla es `private/config.example.php`.
- **Datos que genera el servidor:** `data/`, `feeds/`, `downloads/` y lo mismo dentro de cada versión.
- **Versiones anteriores de tv.yoma.site:** se conservan en el hosting para volver atrás.

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
