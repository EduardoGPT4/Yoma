<?php
/** Install beside YomaTV's existing index.php; no configuration secrets here. */
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
require defined('YOMA_WEB_BOOTSTRAP') ? YOMA_WEB_BOOTSTRAP : __DIR__.'/private/app.php';
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('Referrer-Policy: no-referrer');
$nonce=base64_encode(random_bytes(18));
header("Content-Security-Policy: default-src 'none'; script-src 'nonce-$nonce'; base-uri 'none'; frame-ancestors 'none'");
try {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') throw new WebError('Método no permitido.',405);
    $token = (string)($_SERVER['HTTP_X_YOMASHI_TOKEN'] ?? '');
    if (!preg_match('/^[a-f0-9]{64}$/D', $token)) throw new WebError('Conecta MAL desde Yoma.',401);
    $db = db();
    rate($db, 'yoma-session:'.hash('sha256',$token), 12, 60);
    $device = sql($db, 'SELECT mal_user_id FROM sa1_yomashi_devices WHERE token_hash=? AND expires_at>? AND tokens IS NOT NULL', [hash('sha256',$token),time()])->fetch();
    if (!$device || (int)$device['mal_user_id'] < 1) throw new WebError('La conexión MAL caducó.',401);
    // Possession of the native MAL credential proves the same MAL identity.
    // Never adopt a web account with a different MAL ID or ambiguous mapping.
    $users = sql($db, 'SELECT u.id,u.auth_version FROM sa1_users u JOIN sa1_mal_connections m ON m.user_id=u.id WHERE m.mal_user_id=? AND m.needs_auth=0', [(int)$device['mal_user_id']])->fetchAll();
    if (count($users) !== 1) throw new WebError('Conecta esta misma cuenta MAL una vez en YomaTV. Después podrás compartirla desde Yoma.',409);
    $_SESSION = ['user_id'=>(int)$users[0]['id'], 'auth_version'=>(int)$users[0]['auth_version'], 'csrf'=>bin2hex(random_bytes(24)), 'yoma_device'=>hash('sha256',$token)];
    session_regenerate_id(true);
    // No HTTP redirect: prevents forwarding the native header to another URL.
    echo '<!doctype html><meta name="viewport" content="width=device-width"><p>Cuenta compartida. <a href="./">Abrir YomaTV</a></p><script nonce="'.htmlspecialchars($nonce,ENT_QUOTES,'UTF-8').'">location.replace("./")</script>';
} catch (WebError $e) {
    http_response_code($e->status);
    echo '<!doctype html><meta name="viewport" content="width=device-width"><p>'.htmlspecialchars($e->getMessage(), ENT_QUOTES, 'UTF-8').'</p><a href="./#account">Abrir cuenta de YomaTV</a>';
} catch (Throwable $e) {
    http_response_code(503);
    echo 'No se pudo compartir la sesión. Reintenta desde Yoma.';
}
