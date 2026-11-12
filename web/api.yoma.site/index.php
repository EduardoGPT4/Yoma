<?php
// api.yoma.site: servicios compartidos de Yoma. Esta página dice si el servicio
// está listo (configuración y base de datos) y, si no, el tipo de problema,
// nunca sus detalles (podrían incluir datos de la conexión). La API está en
// yomashi-api.php.
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
header('Content-Type: application/json; charset=utf-8');

/** Tipo de fallo, sin datos: código de MySQL o clase de error de PHP. */
function yoma_api_problem(Throwable $error): string
{
  if ($error instanceof PDOException) {
    $code = preg_match('/\[(\d{4})\]/', $error->getMessage(), $m) ? (int) $m[1] : (int) $error->getCode();
    return match ($code) {
      1044, 1045 => 'acceso_denegado',
      1049 => 'base_no_existe',
      2002, 2003, 2005, 2006 => 'servidor_no_disponible',
      default => 'mysql_' . $code,
    };
  }
  if ($error instanceof RuntimeException && !($error instanceof PDOException)) return 'configuracion';
  return 'php_' . (new ReflectionClass($error))->getShortName();
}

$config = is_file(__DIR__ . '/private/config.local.php');
$database = false;
$problem = $config ? null : 'sin_configuracion';
if ($config) {
  try {
    require __DIR__ . '/private/app.php';
    db()->query('SELECT 1');
    $database = true;
  } catch (Throwable $error) {
    $problem = yoma_api_problem($error);
  }
}
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
echo json_encode(['service' => 'yoma-api', 'ok' => $config && $database, 'config' => $config, 'database' => $database] + ($problem === null ? [] : ['problem' => $problem]) + ['php' => PHP_VERSION, 'pdo_mysql' => extension_loaded('pdo_mysql')]);
