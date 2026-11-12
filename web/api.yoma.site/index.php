<?php
// api.yoma.site: servicios compartidos de Yoma. Esta página dice si el servicio
// está listo (configuración y base de datos), sin mostrar nada de ellas. La API
// está en yomashi-api.php.
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
header('Content-Type: application/json; charset=utf-8');
$config = is_file(__DIR__ . '/private/config.local.php');
$database = false;
if ($config) {
  try {
    require __DIR__ . '/private/app.php';
    db()->query('SELECT 1');
    $database = true;
  } catch (Throwable) {
    // Sin detalles: podrían incluir datos de la conexión.
  }
}
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
echo json_encode(['service' => 'yoma-api', 'ok' => $config && $database, 'config' => $config, 'database' => $database]);
