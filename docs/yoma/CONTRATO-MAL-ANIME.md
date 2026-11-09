# Contrato MAL Anime — Implementado y desplegado

Estado actualizado: implementado en `server/private/yoma-anime-mal.php`, integrado en el despachador común y desplegado con autorización. Evidencia: `deployment/receipt.json`; validación: `INFORME-FINAL-3.0.1.md`.

Se reutilizan las credenciales cifradas de dispositivo, renovación y revocación existentes. El cliente no recibe tokens MAL y ambos módulos utilizan la misma sesión.

- `anime_capabilities`: autentica y devuelve `{ "anime": true, "conflict_check": true }`.
- `anime_library`: filtros watching/completed/on_hold/dropped/plan_to_watch, offset y limit hasta 100. Devuelve items normalizados y next_offset.
- `anime_detail`: ID MAL numérico. Devuelve anime normalizado para asociación explícita o resolución de pendientes.
- `anime_update`: ID, owner_id, episodes_watched y expected_episodes. Compara progreso remoto, impide reducción automática y conserva estados remotos. Responde 409 a conflictos; el cliente conserva el pendiente y ofrece resolución explícita.

Las rutas verificadas del mal-http.php activo son list, anime:<id> y list-status:<id>. Se validan parámetros antes de renovar tokens. Las operaciones de Manga permanecen separadas.

La comparación remota es optimista; no constituye una transacción atómica con otros clientes externos de MAL. No se vinculan cuentas por nombres. No se modificó la lista real del usuario durante las pruebas; la autenticación y cambios de progreso se verificaron contra un proveedor MAL local aislado.
