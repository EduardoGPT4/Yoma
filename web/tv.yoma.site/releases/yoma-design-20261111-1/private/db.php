<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
require_once __DIR__ . '/catalog-source.php';

function db(): PDO
{
  static $pdo;
  if ($pdo) {
    return $pdo;
  }
  $sqlite = getenv('SEASON_WEB_SQLITE');
  $testMysql=getenv('SEASON_WEB_TEST_MYSQL_DSN');
  if ($testMysql && preg_match('/^mysql:host=127\.0\.0\.1;port=33316;dbname=seasonav1_test_[a-f0-9]+;charset=utf8mb4$/D',$testMysql)) {
    $pdo=new PDO($testMysql,'root',(string)getenv('SEASON_WEB_TEST_MYSQL_PASSWORD'));
  } elseif ($sqlite) {
    $pdo = new PDO('sqlite:' . $sqlite);
    $pdo->exec('PRAGMA foreign_keys=ON');
    $pdo->exec('PRAGMA busy_timeout=5000');
  } else {
    $file = __DIR__ . '/config.local.php';
    if (!is_file($file)) {
      throw new RuntimeException(
        'La conexión de este sitio todavía no está configurada.',
      );
    }
    $c = require $file;
    $pdo = new PDO(
      'mysql:host=' .
        $c['host'] .
        ';port=' .
        (int) $c['port'] .
        ';dbname=' .
        $c['database'] .
        ';charset=utf8mb4',
      $c['username'],
      $c['password'],
      [PDO::ATTR_TIMEOUT => 8],
    );
  }
  $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
  $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
  migrate($pdo);
  seed_data($pdo);
  return $pdo;
}

function sql(PDO $db, string $query, array $args = []): PDOStatement
{
  $started=hrtime(true);
  try {$s=$db->prepare($query);$s->execute($args);return $s;}
  finally {if(function_exists('observe_query'))observe_query($query,(hrtime(true)-$started)/1e6);}
}

function upsert(
  PDO $db,
  string $table,
  array $columns,
  array $rows,
  array $keys,
  array $updates,
): void {
  if (!$rows) {
    return;
  }
  if (count($rows) > 100) {
    foreach (array_chunk($rows, 100) as $batch) {
      upsert($db, $table, $columns, $batch, $keys, $updates);
    }
    return;
  }
  $groups = implode(
    ',',
    array_fill(
      0,
      count($rows),
      '(' . implode(',', array_fill(0, count($columns), '?')) . ')',
    ),
  );
  $values = [];
  foreach ($rows as $r) {
    foreach ($columns as $k) {
      $values[] = $r[$k] ?? null;
    }
  }
  $query =
    'INSERT INTO ' .
    $table .
    ' (' .
    implode(',', $columns) .
    ') VALUES ' .
    $groups;
  if ($db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql') {
    $query .=
      ' ON DUPLICATE KEY UPDATE ' .
      implode(',', array_map(fn($k) => $k . '=VALUES(' . $k . ')', $updates));
  } else {
    $query .=
      ' ON CONFLICT(' .
      implode(',', $keys) .
      ') DO UPDATE SET ' .
      implode(',', array_map(fn($k) => $k . '=excluded.' . $k, $updates));
  }
  sql($db, $query, $values);
}

function meta(PDO $db, string $key, ?string $default = null): ?string
{
  $v = sql($db, 'SELECT value FROM sa1_meta WHERE name=?', [
    $key,
  ])->fetchColumn();
  return $v === false ? $default : (string) $v;
}
function set_meta(PDO $db, string $key, string $value): void
{
  upsert(
    $db,
    'sa1_meta',
    ['name', 'value'],
    [['name' => $key, 'value' => $value]],
    ['name'],
    ['value'],
  );
}

require_once __DIR__ . '/migrations.php';

require_once __DIR__.'/runtime.php';
require_once __DIR__.'/public-cache.php';
