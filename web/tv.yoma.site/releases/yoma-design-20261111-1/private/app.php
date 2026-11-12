<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

require __DIR__ . '/bootstrap.php';
require __DIR__ . '/access.php';
require __DIR__ . '/preferences.php';
require __DIR__ . '/catalog.php';
require __DIR__ . '/state.php';
require __DIR__ . '/auth.php';
require __DIR__ . '/library.php';
require __DIR__ . '/library-transfer.php';
require __DIR__ . '/queue.php';
require __DIR__ . '/sync.php';
require __DIR__ . '/mal.php';
require __DIR__ . '/mal-library.php';
require __DIR__ . '/features.php';
require __DIR__ . '/maintenance.php';
require __DIR__ . '/catalog-metadata.php';
require __DIR__ . '/watch-sync.php';
require __DIR__ . '/catalog-updates.php';
require __DIR__ . '/catalog-relations.php';
require __DIR__ . '/calendar-feed.php';
require __DIR__ . '/experience.php';
require __DIR__ . '/match-review.php';
require_once __DIR__ . '/public-cache.php';
require __DIR__ . '/system-health.php';
require __DIR__ . '/personal.php';
require __DIR__ . '/mobile.php';

function dispatch(PDO $db, string $action, array $input): array
{
  validate_session($db);
  if ($action === 'state') {
    return ['data' => state($db)];
  }
  if ($action === 'catalog') {
    return ['catalog' => catalog($db, $input)];
  }
  if ($action === 'queue_history') return queue_history($db, $input);
  if ($action === 'radio') {
    return [
      'radio' => json_decode(
        file_get_contents(dirname(__DIR__) . '/data/radio.json'),
        true,
        512,
        JSON_THROW_ON_ERROR,
      ),
    ];
  }
  if ($action === 'detail') {
    return ['detail' => detail($db, (string) ($input['slug'] ?? ''))];
  }
  if ($action === 'home') {
    return ['home' => home_data($db)];
  }
  if ($action === 'player_state') return player_read_state($db,$input);
  if ($action === 'player') {
    return player_data($db, $input);
  }
  if ($action === 'player_servers') return player_servers($db, $input);
  $response = dispatch_auth($db, $action, $input);
  if ($response !== null) {
    return $response;
  }
  member();
  foreach (
    [
      'dispatch_library',
      'dispatch_queue',
      'dispatch_sync',
      'dispatch_library_transfer',
      'dispatch_mal',
      'dispatch_mal_library',
      'dispatch_features',
      'dispatch_maintenance',
      'dispatch_watch_sync',
      'dispatch_catalog_updates',
      'dispatch_catalog_relations',
      'dispatch_calendar',
      'dispatch_experience',
      'dispatch_match_review',
      'dispatch_system_health',
      'dispatch_personal',
      'dispatch_mobile',
    ]
    as $handler
  ) {
    $response = $handler($db, $action, $input);
    if ($response !== null) {
      return $response;
    }
  }
  throw new WebError('Acción desconocida.', 404);
}
