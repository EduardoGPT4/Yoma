<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}

function validate_session(PDO $db): void
{
  if (!uid()) {
    return;
  }
  $version = sql($db, 'SELECT auth_version FROM sa1_users WHERE id=?', [
    uid(),
  ])->fetchColumn();
  if (
    $version === false ||
    (int) $version !== (int) ($_SESSION['auth_version'] ?? 0)
  ) {
    $_SESSION = ['csrf' => bin2hex(random_bytes(24))];
    session_regenerate_id(true);
  }
}

function new_password(array $input): string
{
  $password = (string) ($input['new_password'] ?? ($input['password'] ?? ''));
  if (mb_strlen($password) < 8) {
    throw new WebError('Usa una contraseña de al menos 8 caracteres.');
  }
  if (strlen($password) > 72) {
    throw new WebError(
      'La contraseña es demasiado larga. Prueba con menos caracteres.',
    );
  }
  if (
    isset($input['password_confirm']) &&
    !hash_equals($password, (string) $input['password_confirm'])
  ) {
    throw new WebError('Las contraseñas nuevas no coinciden.');
  }
  return $password;
}

function verify_current_password(PDO $db, array $input): array
{
  $user = member();
  rate($db, 'account-password:' . $user, 12, 300);
  $row = sql($db, 'SELECT * FROM sa1_users WHERE id=?', [$user])->fetch();
  $password = (string) ($input['current_password'] ?? '');
  if (
    strlen($password) > 200 ||
    !$row ||
    !password_verify($password, $row['password_hash'])
  ) {
    throw new WebError('La contraseña actual no es correcta.', 403);
  }
  return $row;
}

function account_info(PDO $db): array
{
  $user = member();
  $row = sql($db, 'SELECT id,name,email FROM sa1_users WHERE id=?', [
    $user,
  ])->fetch();
  $notice = $_SESSION['mal_notice'] ?? null;
  unset($_SESSION['mal_notice']);
  $stored=sql($db,'SELECT notice,created_at FROM sa1_user_notices WHERE user_id=?',[$user])->fetch();
  if($stored){$notice=$notice??((int)$stored['created_at']>time()-86400?$stored['notice']:null);sql($db,'DELETE FROM sa1_user_notices WHERE user_id=? AND notice=? AND created_at=?',[$user,$stored['notice'],$stored['created_at']]);}
  return array_merge($row, [
    'is_admin' => administrator($db),
    'mal' => mal_status($db),
    'mal_notice' => $notice,
    'recovery_remaining' => (int) sql(
      $db,
      'SELECT COUNT(*) FROM sa1_recovery WHERE user_id=? AND used_at IS NULL',
      [$user],
    )->fetchColumn(),
  ]);
}

function dispatch_auth(PDO $db, string $action, array $input): ?array
{
  if ($action === 'mal_login') {
    return ['authorization_url' => mal_login_begin($db)];
  }
  // Las cuentas nuevas se crean al iniciar sesión con MyAnimeList.
  if ($action === 'register') {
    throw new WebError('Para crear tu cuenta, inicia sesión con MyAnimeList.', 403);
  }
  // Con correo solo entra una cuenta antigua, una vez, para conectar MAL.
  if ($action === 'login') {
    rate(
      $db,
      'auth:' . hash('sha256', $_SERVER['REMOTE_ADDR'] ?? 'local'),
      12,
      300,
    );
    $email = mb_strtolower(trim((string) ($input['email'] ?? '')));
    $password = (string) ($input['password'] ?? '');
    rate($db,'auth-email:'.hash('sha256',$email),12,300);
    if (
      !filter_var($email, FILTER_VALIDATE_EMAIL) ||
      strlen($email) > 190 ||
      strlen($password) > 200
    ) {
      throw new WebError('Escribe un correo y una contraseña válidos.');
    }
    $initialCodes=null;
    $row = sql($db, 'SELECT * FROM sa1_users WHERE email=?', [
      $email,
    ])->fetch();
    if (!$row || !password_verify($password, $row['password_hash'])) {
      throw new WebError('Correo o contraseña incorrectos.', 401);
    }
    // Ya vinculada: solo entra con MyAnimeList. El correo sirve una vez,
    // para vincular una cuenta antigua.
    if (mal_login_linked($db, (int) $row['id'])) {
      throw new WebError('Esta cuenta ya entra con MyAnimeList. Usa «Iniciar sesión con MyAnimeList».', 403);
    }
    $_SESSION['user_id'] = (int) $row['id'];
    $_SESSION['auth_version'] = (int) $row['auth_version'];
    session_regenerate_id(true);
    $_SESSION['csrf'] = bin2hex(random_bytes(24));
    return [
      'recovery_codes'=>$initialCodes,
      'link_mal' => true,
      'message' => 'Cuenta encontrada. Conecta MyAnimeList para vincularla.',
      'data' => state($db),
    ];
  }
  if ($action === 'logout') {
    $_SESSION = ['csrf' => bin2hex(random_bytes(24))];
    session_regenerate_id(true);
    return ['data' => state($db), 'message' => 'Sesión cerrada.'];
  }
  if ($action === 'account_recover') {
    rate(
      $db,
      'recovery-ip:' . hash('sha256', $_SERVER['REMOTE_ADDR'] ?? 'local'),
      6,
      900,
    );
    $email = mb_strtolower(trim((string) ($input['email'] ?? '')));
    rate($db, 'recovery-email:' . hash('sha256', $email), 6, 900);
    $password = new_password($input);
    $code = strtolower(
      preg_replace('/[\s-]+/', '', (string) ($input['recovery_code'] ?? '')),
    );
    $row = sql($db, 'SELECT * FROM sa1_users WHERE email=?', [$email])->fetch();
    $invalid = 'El correo o el código de recuperación no es válido.';
    if (!$row || !preg_match('/^[a-f0-9]{32}$/', $code)) {
      throw new WebError($invalid, 403);
    }
    $db->beginTransaction();
    try {
      $consumed = sql(
        $db,
        'UPDATE sa1_recovery SET used_at=? WHERE user_id=? AND code_hash=? AND used_at IS NULL',
        [time(), $row['id'], hash('sha256', $code)],
      );
      if ($consumed->rowCount() !== 1) {
        throw new WebError($invalid, 403);
      }
      sql(
        $db,
        'UPDATE sa1_users SET password_hash=?,auth_version=auth_version+1 WHERE id=?',
        [password_hash($password, PASSWORD_DEFAULT), $row['id']],
      );
      log_event(
        $db,
        (int) $row['id'],
        'Contraseña recuperada con un código de un solo uso.',
      );
      $db->commit();
    } catch (Throwable $error) {
      $db->rollBack();
      throw $error;
    }
    $_SESSION = ['csrf' => bin2hex(random_bytes(24))];
    session_regenerate_id(true);
    return [
      'message' =>
        'Contraseña actualizada. Inicia sesión con la nueva contraseña.',
      'data' => state($db),
    ];
  }
  if ($action === 'account') {
    return ['account' => account_info($db)];
  }
  if ($action === 'account_password') {
    $row = verify_current_password($db, $input);
    $password = new_password($input);
    sql(
      $db,
      'UPDATE sa1_users SET password_hash=?,auth_version=auth_version+1 WHERE id=?',
      [password_hash($password, PASSWORD_DEFAULT), $row['id']],
    );
    $_SESSION['auth_version'] = (int) $row['auth_version'] + 1;
    session_regenerate_id(true);
    $_SESSION['csrf'] = bin2hex(random_bytes(24));
    $event = log_event(
      $db,
      uid(),
      'Contraseña cambiada. Las otras sesiones se cerraron.',
    );
    return [
      'message' => 'Contraseña actualizada. Las otras sesiones se cerraron.',
      'patch' => state_patch($db, [], [], ['history' => [$event]]),
    ];
  }
  if ($action === 'account_recovery_codes') {
    $row = verify_current_password($db, $input);
    $codes=create_recovery_codes($db,(int)$row['id']);
    $event=log_event($db,uid(),'Códigos de recuperación renovados. Los anteriores dejaron de ser válidos.');
    return [
      'recovery_codes' => $codes,
      'account' => account_info($db),
      'message' => 'Guarda estos códigos. Cada uno se puede usar una sola vez.',
      'patch' => state_patch($db, [], [], ['history' => [$event]]),
    ];
  }
  if ($action === 'account_delete') {
    // Una cuenta que entra con MyAnimeList no usa contraseña.
    $row = mal_login_linked($db, member())
      ? sql($db, 'SELECT * FROM sa1_users WHERE id=?', [member()])->fetch()
      : verify_current_password($db, $input);
    if (($input['confirmation'] ?? '') !== 'ELIMINAR') {
      throw new WebError('Escribe ELIMINAR para confirmar.');
    }
    if (administrator($db)) {
      throw new WebError(
        'Primero asigna otra cuenta administradora antes de eliminar esta cuenta.',
      );
    }
    $feed=sql($db,'SELECT feed_key FROM sa1_calendar_feeds WHERE user_id=?',[$row['id']])->fetchColumn();
    $db->beginTransaction();
    try {
      sql($db, 'DELETE FROM sa1_users WHERE id=?', [$row['id']]);
      $db->commit();
      if ($feed && is_file(calendar_feed_path($feed))) unlink(calendar_feed_path($feed));
    } catch (Throwable $error) {
      $db->rollBack();
      throw $error;
    }
    $_SESSION = ['csrf' => bin2hex(random_bytes(24))];
    session_regenerate_id(true);
    return ['message' => 'Cuenta eliminada.', 'data' => state($db)];
  }
  return null;
}

function create_recovery_codes(PDO $db,int $user): array
{
  $codes=[];$own=!$db->inTransaction();if($own)$db->beginTransaction();
  try{
    sql($db,'DELETE FROM sa1_recovery WHERE user_id=?',[$user]);
    for($n=0;$n<10;$n++){$raw=bin2hex(random_bytes(16));$codes[]=implode('-',str_split($raw,8));sql($db,'INSERT INTO sa1_recovery(user_id,code_hash,created_at) VALUES(?,?,?)',[$user,hash('sha256',$raw),time()]);}
    if($own)$db->commit();return $codes;
  }catch(Throwable $error){if($own&&$db->inTransaction())$db->rollBack();throw $error;}
}
