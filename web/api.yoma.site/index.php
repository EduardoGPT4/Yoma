<?php
// api.yoma.site: servicios compartidos de Yoma. Esta página solo dice que el
// servicio está publicado; la API está en yomashi-api.php.
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
echo json_encode(['service' => 'yoma-api', 'ok' => is_file(__DIR__.'/private/config.local.php')]);
