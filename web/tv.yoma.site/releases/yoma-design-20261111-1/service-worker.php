<?php
declare(strict_types=1);
header('Content-Type: application/javascript; charset=utf-8');
header('Cache-Control: no-cache');
header('Service-Worker-Allowed: ./');
header('X-Content-Type-Options: nosniff');
readfile(__DIR__.'/sw.js');
