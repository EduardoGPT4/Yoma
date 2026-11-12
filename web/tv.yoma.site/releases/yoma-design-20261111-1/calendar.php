<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED',true);
require __DIR__.'/private/app.php';
try {
  validate_session(db());
  $scope=(string)($_GET['scope']??'all');
  if (!in_array($scope,['all','followed'],true)) throw new WebError('Filtro de calendario inválido.');
  if ($scope==='followed') member();
  header('Content-Type: text/calendar; charset=utf-8');
  header('Content-Disposition: attachment; filename="YomaTV-horario.ics"');
  echo calendar_body(db(),uid(),$scope);
} catch (WebError $error) {http_response_code($error->status);header('Content-Type: text/plain; charset=utf-8');echo $error->getMessage();}
