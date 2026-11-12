<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

function mal_identity_id(PDO $db): int
{
  return (int) (sql($db, 'SELECT mal_user_id FROM sa1_mal_identity WHERE user_id=?', [uid()])->fetchColumn()
    ?: sql($db, 'SELECT mal_user_id FROM sa1_mal_connections WHERE user_id=?', [uid()])->fetchColumn());
}

// Caller holds its transaction. Local follows, notes, files and watched marks are independent.
function mal_bind_identity(PDO $db, int $account): bool
{
  $previous = mal_identity_id($db);
  $stored = sql($db,'SELECT mal_user_id FROM sa1_mal_identity WHERE user_id=?',[uid()])->fetchColumn();
  $unknown = $stored !== false && (int)$stored === 0;
  $changed = $unknown || ($previous > 0 && $previous !== $account);
  if ($changed) {
    foreach (['sa1_mal_list','sa1_mal_links','sa1_mal_sync'] as $table)
      sql($db, "DELETE FROM $table WHERE user_id=?", [uid()]);
    sql($db, "UPDATE sa1_watch_sync SET state='blocked',error_kind=?,generation=?,mal_account_id=CASE WHEN mal_account_id=0 THEN ? ELSE mal_account_id END WHERE user_id=?",
      [$unknown?'identity_unknown':'account_changed',bin2hex(random_bytes(16)), $previous, uid()]);
  } else {
    // Marks made before the first authorization belong to the first account selected by the user.
    sql($db, 'UPDATE sa1_watch_sync SET mal_account_id=? WHERE user_id=? AND mal_account_id=0', [$account, uid()]);
  }
  upsert($db, 'sa1_mal_identity', ['user_id','mal_user_id'],
    [['user_id'=>uid(),'mal_user_id'=>$account]], ['user_id'], ['mal_user_id']);
  return $changed;
}

function mal_assert_account(PDO $db, int $account): void
{
  $current = (int) sql($db, 'SELECT mal_user_id FROM sa1_mal_connections WHERE user_id=? AND needs_auth=0', [uid()])->fetchColumn();
  if ($current !== $account || $account < 1)
    throw new WebError('La cuenta de MyAnimeList cambió. Reabre la ficha antes de continuar.', 409);
}

function mal_is_removed(PDO $db, int $account, int $id): bool
{
  return (bool) sql($db, 'SELECT 1 FROM sa1_mal_removed WHERE user_id=? AND mal_account_id=? AND mal_id=?',
    [uid(), $account, $id])->fetchColumn();
}

function mal_allow_title(PDO $db, int $account, int $id): void
{
  sql($db, 'DELETE FROM sa1_mal_removed WHERE user_id=? AND mal_account_id=? AND mal_id=?', [uid(), $account, $id]);
}

function mal_cancel_title(PDO $db, int $account, int $id): string
{
  $generation = bin2hex(random_bytes(16));
  $db->beginTransaction();
  try {
    $suffix = $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql' ? ' FOR UPDATE' : '';
    $where = 'user_id=? AND (mal_id=? OR slug IN (SELECT slug FROM sa1_mal_links WHERE user_id=? AND mal_id=?))';
    $scope = [uid(), $id, uid(), $id];
    $jobs = sql($db, 'SELECT lock_until FROM sa1_watch_sync WHERE ' . $where . $suffix, $scope)->fetchAll();
    foreach ($jobs as $job) if ((int)$job['lock_until'] > time())
      throw new WebError('Se está terminando una sincronización de este anime. Vuelve a retirarlo en unos segundos.', 409);
    upsert($db, 'sa1_mal_removed', ['user_id','mal_account_id','mal_id','removed_at'],
      [['user_id'=>uid(),'mal_account_id'=>$account,'mal_id'=>$id,'removed_at'=>time()]],
      ['user_id','mal_account_id','mal_id'], ['removed_at']);
    sql($db, "UPDATE sa1_watch_sync SET state='blocked',error_kind='removed',generation=?,lock_until=? WHERE " . $where,
      array_merge([$generation, time()+90], $scope));
    $db->commit();
  } catch (Throwable $error) { $db->rollBack(); throw $error; }
  return $generation;
}
