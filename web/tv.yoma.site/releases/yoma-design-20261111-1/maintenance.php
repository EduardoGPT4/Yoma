<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
require __DIR__ . '/private/app.php';
header('Content-Type: application/json; charset=utf-8');
try {
  if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    throw new WebError('Usa POST con un token de actualización.', 405);
  }
  if (!external_maintenance_enabled()) {
    throw new WebError(
      'La actualización externa está desactivada en este alojamiento.',
      403,
    );
  }
  $header = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? '');
  $token = preg_match('/^Bearer ([a-f0-9]{64})$/D', $header, $match)
    ? $match[1]
    : '';
  $hash = meta(db(), 'maintenance_token_hash', '');
  if (!$hash || !hash_equals($hash, hash('sha256', $token))) {
    throw new WebError('Token de actualización no válido.', 403);
  }
  define('SEASON_SYSTEM_REFRESH', true);
  echo json_encode(
    ['ok' => true, 'result' => maintenance_run(db())],
    JSON_UNESCAPED_UNICODE,
  );
} catch (WebError $e) {
  http_response_code($e->status);
  echo json_encode(['ok' => false, 'message' => $e->getMessage()]);
} catch (Throwable $e) {
  http_response_code(503);
  echo json_encode([
    'ok' => false,
    'message' => 'No se pudo actualizar. Se conservan los datos anteriores.',
  ]);
}
