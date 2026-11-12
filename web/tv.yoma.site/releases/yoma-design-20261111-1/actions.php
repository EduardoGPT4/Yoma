<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
require __DIR__ . '/private/app.php';
header('Content-Type: application/json; charset=utf-8');
try {
  if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (
      !hash_equals(
        $_SESSION['csrf'],
        (string) ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? ''),
      )
    ) {
      throw new WebError(
        'La sesión cambió. Recarga la página e inténtalo de nuevo.',
        403,
      );
    }
    $transfer = ($_GET['transfer'] ?? '') === 'library';
    $maximum = ($transfer ? 12 : 2) * 1024 * 1024;
    if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > $maximum) {
      throw new WebError('El archivo excede el tamaño permitido.', 413);
    }
    $raw = file_get_contents('php://input', false, null, 0, $maximum + 1);
    if (strlen($raw) > $maximum) {
      throw new WebError('El archivo excede el tamaño permitido.', 413);
    }
    $input = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
    if (!is_array($input)) {
      throw new WebError('Solicitud inválida.');
    }
    $action = (string) ($input['action'] ?? '');
    if ($transfer && !in_array($action, ['library_import', 'mal_xml'], true)) {
      throw new WebError('Solicitud de transferencia inválida.');
    }
  } else {
    if($_SERVER['REQUEST_METHOD']!=='GET')throw new WebError('Método HTTP no admitido.',405);
    $input = $_GET;
    $action = (string) ($input['action'] ?? 'state');
    if (
      !in_array(
        $action,
        [
          'state',
          'detail',
          'catalog',
          'queue_history',
          'queue_page',
          'radio',
          'account',
          'library_export',
          'home',
          'mal_cached',
          'mal_entry',
          'player_state',
          'personal',
          'sync_inbox',
          'catalog_task',
          'stats',
          'notifications',
          'maintenance_status',
          'saved_filters',
          'calendar_feed',
          'presence',
          'system_health',
          'mobile_session',
        ],
        true,
      )
    ) {
      throw new WebError('Usa una solicitud POST para guardar cambios.', 405);
    }
  }
  observation_start($action);
  request_limits(db(),$action);
  $response = dispatch(db(), $action, $input);
  // Keep already-open older clients working while the current UI uses patches.
  if (
    isset($response['patch']) &&
    ($_SERVER['HTTP_X_SEASON_RESPONSE'] ?? '') !== 'patch'
  ) {
    unset($response['patch']);
    $response['data'] = state(db(), true);
  }
  echo json_encode(
    array_merge(['ok' => true], $response),
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR,
  );
} catch (WebError $e) {
  $requestError=$e;
  http_response_code($e->status);
  echo json_encode(
    ['ok' => false, 'message' => $e->getMessage()],
    JSON_UNESCAPED_UNICODE,
  );
} catch (ScraperError $e) {
  $requestError=$e;
  try {
    record_scraper_failure(db(), $e->getMessage());
  } catch (Throwable $ignored) {
  }
  http_response_code(503);
  echo json_encode(
    ['ok' => false, 'message' => $e->getMessage()],
    JSON_UNESCAPED_UNICODE,
  );
} catch (JsonException $e) {
  $requestError=$e;
  http_response_code(400);
  echo json_encode([
    'ok' => false,
    'message' => 'El JSON no tiene un formato válido.',
  ]);
} catch (Throwable $e) {
  $requestError=$e;
  error_log('YomaTVWeb: ' . get_class($e) . ' code ' . $e->getCode());
  http_response_code(503);
  echo json_encode(
    [
      'ok' => false,
      'message' =>
        'No se pudo completar la operación. Tus datos se conservaron; intenta más tarde.',
    ],
    JSON_UNESCAPED_UNICODE,
  );
}

if(session_status()===PHP_SESSION_ACTIVE)session_write_close();
if(isset($action))try{observation_finish(db(),$requestError??null);}catch(Throwable $ignored){}
