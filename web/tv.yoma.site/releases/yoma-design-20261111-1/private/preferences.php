<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function defaults(): array
{
  return [
    'language' => 'SUB',
    'server' => 'MP4Upload',
    'height' => 1080,
    'quality_fallback' => 'best',
    'language_fallback' => 'wait',
    'server_fallback' => 'wait',
    'review_time' => '12:00',
    'workers' => 1,
    'speed_kib' => 0,
    'selection' => 'all',
    'long_series' => 'keep',
    'season_source' => 'current',
  ];
}

function preferences(PDO $db, int $user): array
{
  $row = sql($db, 'SELECT settings FROM sa1_preferences WHERE user_id=?', [
    $user,
  ])->fetchColumn();
  return array_replace(defaults(), $row ? json_decode($row, true) : []);
}

function valid_preferences(array $input): array
{
  $result = defaults();
  foreach ($result as $key => $default) {
    if (array_key_exists($key, $input)) {
      $result[$key] = is_int($default)
        ? filter_var($input[$key], FILTER_VALIDATE_INT)
        : trim((string) $input[$key]);
    }
  }
  $sets = [
    'language' => ['SUB', 'LAT', 'DUB'],
    'server' => ['MP4Upload', 'Voe'],
    'height' => [720, 1080],
    'quality_fallback' => ['best', 'lower', 'wait'],
    'language_fallback' => ['wait', 'SUB'],
    'server_fallback' => ['wait', 'other'],
    'selection' => ['all', 'favorites'],
    'long_series' => ['keep', 'split'],
    'season_source' => ['current', 'premiere'],
  ];
  foreach ($sets as $key => $values) {
    if (!in_array($result[$key], $values, true)) {
      throw new WebError('Preferencia inválida: ' . $key . '.');
    }
  }
  if (
    !preg_match('/^(?:[01]\d|2[0-3]):[0-5]\d$/', $result['review_time']) ||
    $result['workers'] < 1 ||
    $result['workers'] > 4 ||
    $result['speed_kib'] < 0 ||
    $result['speed_kib'] > 1000000
  ) {
    throw new WebError('Revisa la hora y los límites de descarga.');
  }
  return $result;
}
