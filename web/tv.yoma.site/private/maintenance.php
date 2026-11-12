<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
function external_maintenance_enabled(): bool
{
  $file = __DIR__ . '/config.local.php';
  $config = is_file($file) ? require $file : [];
  return ($config['external_maintenance'] ?? false) === true;
}
function maintenance_status(PDO $db): array
{
  return [
    'last_attempt' => (int) meta($db, 'maintenance_attempt', '0'),
    'last_success' => (int) meta($db, 'maintenance_success', '0'),
    'last_schedule_success' => (int) meta($db, 'maintenance_schedule_success', '0'),
    'error' => meta($db, 'scraper_error', ''),
    'error_at' => (int) meta($db, 'scraper_error_at', '0'),
    'token_configured' => (bool) meta($db, 'maintenance_token_hash'),
    'external_enabled' => external_maintenance_enabled(),
    'catalog_jobs' => catalog_jobs_status($db),
    'catalog_due' => (int)meta($db,'directory_next_cycle','0')<=time() || (bool)sql($db,"SELECT task_key FROM sa1_catalog_tasks WHERE (state='pending' AND next_retry<=?) OR (state='running' AND lock_until<=?) LIMIT 1",[time(),time()])->fetchColumn() || (bool)sql($db,'SELECT a.slug FROM sa1_anime a LEFT JOIN sa1_catalog_freshness f ON f.slug=a.slug WHERE COALESCE(f.episodes_at,0)<CAST(? AS SIGNED) LIMIT 1',[time()-2592000])->fetchColumn(),
    'interval_hours' => 12,
    'next_due' => (int) meta($db, 'maintenance_next_due', '0'),
    'remaining' => count(
      json_decode(meta($db, 'maintenance_pending', '[]'), true) ?: [],
    ),
    'quarantined' => count(json_decode(meta($db, 'maintenance_quarantine', '[]'), true) ?: []),
  ];
}
function record_scraper_failure(PDO $db, string $message): void
{
  set_meta($db, 'scraper_error', mb_substr($message, 0, 500));
  set_meta($db, 'scraper_error_at', (string) time());
}
function maintenance_run(PDO $db): array
{
  if ((int)meta($db,'maintenance_next_due','0')<=time()) return schedule_maintenance_run($db);
  $turn=(int)meta($db,'maintenance_turn','0')+1;set_meta($db,'maintenance_turn',(string)$turn);
  $pending=json_decode(meta($db,'maintenance_pending','[]'),true)?:[];
  if ($pending && $turn%2===1) return maintenance_step($db)+['catalog_pending'=>true];
  return catalog_jobs_step($db);
}
function schedule_maintenance_run(PDO $db): array
{
  upsert(
    $db,
    'sa1_meta',
    ['name', 'value'],
    [['name' => 'maintenance_next_due', 'value' => '0']],
    ['name'],
    ['name'],
  );
  $due = meta($db, 'maintenance_next_due', '0');
  if ((int) $due > time()) {
    return maintenance_step($db);
  }
  // Atomic database lease prevents visits and the external runner from overlapping.
  $lock = sql($db, 'UPDATE sa1_meta SET value=? WHERE name=? AND value=?', [
    (string) (time() + 43200),
    'maintenance_next_due',
    $due,
  ]);
  if ($lock->rowCount() !== 1) {
    return ['skipped' => true, 'reason' => 'Otra revisión ya está en curso.'];
  }
  set_meta($db, 'maintenance_attempt', (string) time());
  try {
    $before = [];
    foreach (sql($db, 'SELECT slug,latest FROM sa1_anime')->fetchAll() as $r) {
      $before[$r['slug']] = $r['latest'];
    }
    $count = sync_schedule($db);
    $pending = json_decode(meta($db, 'maintenance_pending', '[]'), true) ?: [];
    $quarantine = json_decode(meta($db, 'maintenance_quarantine', '[]'), true) ?: [];
    foreach (
      sql(
        $db,
        'SELECT slug,latest,catalog_complete FROM sa1_anime WHERE active=1 ORDER BY weekday,title',
      )->fetchAll()
      as $r
    ) {
      if (
        !$r['catalog_complete'] ||
        ($before[$r['slug']] ?? '') !== $r['latest']
      ) {
        if (!isset($quarantine[$r['slug']])) $pending[] = $r['slug'];
      }
    }
    $pending = array_values(array_unique($pending));
    set_meta($db, 'maintenance_pending', json_encode($pending));
    set_meta($db, 'maintenance_schedule_success', (string) time());
    if (!$pending && !$quarantine) set_meta($db, 'maintenance_success', (string) time());
    set_meta($db, 'scraper_error', '');
    return [
      'skipped' => false,
      'anime' => $count,
      'remaining' => count($pending),
    ];
  } catch (Throwable $error) {
    set_meta($db, 'maintenance_next_due', (string) (time() + 900));
    record_scraper_failure(
      $db,
      'No se pudo actualizar el horario. Se conservan los datos: ' .
        $error->getMessage(),
    );
    throw $error;
  }
}
function maintenance_step(PDO $db): array
{
  $pending = json_decode(meta($db, 'maintenance_pending', '[]'), true) ?: [];
  if (!$pending) {
    return [
      'skipped' => true,
      'remaining' => 0,
      'reason' => 'El horario y los capítulos ya están al día.',
    ];
  }
  $failures = json_decode(meta($db, 'maintenance_failures', '[]'), true) ?: [];
  $ready = array_values(array_filter($pending, static fn($slug) => (int)($failures[$slug]['next_retry'] ?? 0) <= time()));
  if (!$ready) {
    return [
      'skipped' => true,
      'remaining' => count($pending),
      'next_retry' => min(array_map(static fn($slug)=>(int)$failures[$slug]['next_retry'], $pending)),
      'reason' => 'Las fichas pendientes están esperando su próximo reintento.',
    ];
  }
  upsert(
    $db,
    'sa1_meta',
    ['name', 'value'],
    [['name' => 'maintenance_step_lock', 'value' => '0']],
    ['name'],
    ['name'],
  );
  $old = meta($db, 'maintenance_step_lock', '0');
  if (
    (int) $old > time() ||
    sql($db, 'UPDATE sa1_meta SET value=? WHERE name=? AND value=?', [
      (string) (time() + 30),
      'maintenance_step_lock',
      $old,
    ])->rowCount() !== 1
  ) {
    return [
      'skipped' => true,
      'remaining' => count($pending),
      'reason' => 'Otra revisión ya está en curso.',
    ];
  }
  try {
    // One HTML page per request; no video bytes pass through the hosting account.
    usleep(2100000);
    $slug = (string) $ready[0];
    sync_anime($db, $slug);
    $pending = array_values(array_diff($pending, [$slug]));
    unset($failures[$slug]);
    set_meta($db, 'maintenance_failures', json_encode($failures));
    set_meta($db, 'maintenance_pending', json_encode($pending));
    if (!$pending && !(json_decode(meta($db, 'maintenance_quarantine', '[]'), true) ?: [])) {
      set_meta($db, 'maintenance_success', (string) time());
      set_meta($db, 'scraper_error', '');
    }
    return [
      'skipped' => false,
      'updated_slug' => $slug,
      'remaining' => count($pending),
    ];
  } catch (Throwable $error) {
    $attempts = (int)($failures[$slug]['attempts'] ?? 0) + 1;
    $failure = ['attempts'=>$attempts,'next_retry'=>time()+min(900,60*2**min(4,$attempts-1)),
      'error'=>mb_substr($error->getMessage(),0,300)];
    $pending = array_values(array_diff($pending, [$slug]));
    if ($attempts >= 5) {
      $quarantine = json_decode(meta($db, 'maintenance_quarantine', '[]'), true) ?: [];
      $quarantine[$slug] = $failure;
      set_meta($db, 'maintenance_quarantine', json_encode($quarantine));
      unset($failures[$slug]);
    } else { $pending[] = $slug; $failures[$slug] = $failure; }
    set_meta($db, 'maintenance_pending', json_encode($pending));
    set_meta($db, 'maintenance_failures', json_encode($failures));
    record_scraper_failure(
      $db,
      'No se pudo actualizar «' . $slug . '» (intento ' . $attempts . '). Los demás animes continúan. ' .
        $error->getMessage(),
    );
    return ['skipped'=>false,'failed_slug'=>$slug,'remaining'=>count($pending),'quarantined'=>$attempts>=5];
  } finally {
    set_meta($db, 'maintenance_step_lock', '0');
  }
}
function dispatch_maintenance(PDO $db, string $action, array $input): ?array
{
  if (
    !in_array(
      $action,
      ['maintenance', 'maintenance_token', 'maintenance_status', 'maintenance_retry_failed'],
      true,
    )
  ) {
    return null;
  }
  admin_member($db);
  if ($action === 'maintenance_status') {
    return ['maintenance' => maintenance_status($db)];
  }
  if ($action === 'maintenance_retry_failed') {
    rate($db, 'maintenance-retry-failed', 1, 60);
    $quarantine = json_decode(meta($db, 'maintenance_quarantine', '[]'), true) ?: [];
    $pending = json_decode(meta($db, 'maintenance_pending', '[]'), true) ?: [];
    set_meta($db, 'maintenance_pending', json_encode(array_values(array_unique(array_merge($pending,array_keys($quarantine))))));
    set_meta($db, 'maintenance_quarantine', '[]');
    set_meta($db, 'scraper_error', '');
    return ['message'=>'Las fichas con errores vuelven a la cola de actualización.','home'=>home_data($db)];
  }
  if ($action === 'maintenance_token') {
    if (!external_maintenance_enabled()) {
      throw new WebError(
        'La actualización externa está desactivada. InfinityFree gratuito no admite cron externos; se revisa al visitar como administrador.',
        409,
      );
    }
    verify_current_password($db, $input);
    $token = bin2hex(random_bytes(32));
    set_meta($db, 'maintenance_token_hash', hash('sha256', $token));
    return [
      'maintenance_token' => $token,
      'endpoint' => 'https://tv.yoma.site/maintenance.php',
      'maintenance' => maintenance_status($db),
    ];
  }
  return [
    'maintenance_result' => maintenance_run($db),
    'home' => home_data($db),
    'patch' => state_patch(
      $db,
      [],
      [],
      ['refresh_anime' => true, 'catalog' => true],
    ),
  ];
}
