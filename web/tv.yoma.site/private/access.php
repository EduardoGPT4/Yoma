<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function admin_emails(): array
{
  static $emails;
  if ($emails !== null) {
    return $emails;
  }
  $file = __DIR__ . '/access.local.php';
  $config = is_file($file) ? require $file : [];
  $values = $config['admin_emails'] ?? [];
  if (getenv('SEASON_WEB_SQLITE') && getenv('SEASON_WEB_ADMIN_EMAILS')) {
    $values = explode(',', getenv('SEASON_WEB_ADMIN_EMAILS'));
  }
  $emails = [];
  foreach ($values as $email) {
    $email = mb_strtolower(trim((string) $email));
    if (filter_var($email, FILTER_VALIDATE_EMAIL)) {
      $emails[] = $email;
    }
  }
  return array_values(array_unique($emails));
}

function administrator(PDO $db): bool
{
  if (!uid()) {
    return false;
  }
  $email = sql($db, 'SELECT email FROM sa1_users WHERE id=?', [
    uid(),
  ])->fetchColumn();
  return $email !== false &&
    in_array(mb_strtolower((string) $email), admin_emails(), true);
}

function admin_member(PDO $db): int
{
  $user = member();
  if (!administrator($db)) {
    throw new WebError(
      'Solo el administrador puede actualizar los datos de AnimeAV1.',
      403,
    );
  }
  return $user;
}
