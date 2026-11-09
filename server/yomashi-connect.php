<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
require __DIR__.'/private/yomashi-mal.php';
header('Referrer-Policy: no-referrer');
// Chromium applies form-action to the POST's redirects as well. Replace the
// inherited policy on this page, preserving every directive except this allowlist.
foreach(headers_list() as $existingHeader) {
  if(stripos($existingHeader,'Content-Security-Policy:')!==0) continue;
  $policy=preg_replace('/\bform-action\s+[^;]+/i',"form-action 'self' https://myanimelist.net",$existingHeader,1,$replaced);
  if($replaced===1) header($policy,true);
  break;
}
try {
  $id=(string)($_POST['device']??$_GET['device']??'');
  if(!preg_match('/^[a-f0-9]{32}$/D',$id)) throw new WebError('Inicia la conexión desde YomaShi.',400);
  if($_SERVER['REQUEST_METHOD']==='POST') {
    if(!is_string($_POST['csrf']??null) || !hash_equals($_SESSION['csrf'],$_POST['csrf'])) throw new WebError('La sesión caducó. Recarga la página.',403);
    header('Location: '.ys_begin(db(),$id),true,303);exit;
  }
  if($_SERVER['REQUEST_METHOD']!=='GET') throw new WebError('Método no permitido.',405);
  $csrf=htmlspecialchars($_SESSION['csrf'],ENT_QUOTES,'UTF-8');
  echo '<!doctype html><html lang="es"><meta name="viewport" content="width=device-width"><title>Conectar YomaShi</title><body style="font:18px system-ui;max-width:36em;margin:3em auto;padding:1em"><h1>Conectar YomaShi con MyAnimeList</h1><p>Comprueba que este código coincide con el que aparece en YomaShi:</p><strong>'.strtoupper(substr($id,0,6)).'</strong><p>Permitirás buscar mangas y actualizar tus capítulos leídos y estado. No se cambiará tu lista de anime.</p><form method="post"><input type="hidden" name="device" value="'.$id.'"><input type="hidden" name="csrf" value="'.$csrf.'"><button>Autorizar en MyAnimeList</button></form><p>Continúa solo si acabas de iniciar esta conexión en tu teléfono.</p></body></html>';
} catch(WebError $e) { http_response_code($e->status);echo htmlspecialchars($e->getMessage(),ENT_QUOTES,'UTF-8'); }
catch(Throwable $e) { http_response_code(503);echo 'Conexión no disponible. Reintenta desde YomaShi.'; }
