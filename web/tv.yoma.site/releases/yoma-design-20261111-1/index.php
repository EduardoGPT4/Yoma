<?php
declare(strict_types=1);
define('SEASON_BOOTSTRAPPED', true);
require __DIR__ . '/private/app.php';
$csrf = htmlspecialchars($_SESSION['csrf'], ENT_QUOTES, 'UTF-8');
?>
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Explora todo el catálogo de AnimeAV1, descarga capítulos con YomaTV y escucha música de anime en la radio de YouTube.">
  <meta name="csrf-token" content="<?= $csrf ?>">
  <meta name="bridge-port" content="<?= $bridgePort ?>">
  <meta name="desktop-download-url" content="https://github.com/EduardoGPT4/YomaTV/releases/latest/download/YomaTV-Windows.exe">
  <meta name="theme-color" content="#101014"><title>YomaTV · Tu anime, a tu ritmo</title>
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/fonts.css?v=20261023-medianoche">
  <meta name="application-name" content="YomaTV">
  <meta name="apple-mobile-web-app-title" content="YomaTV">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <link rel="manifest" href="app-manifest.php" crossorigin="use-credentials">
  <script src="releases/yoma-design-20261111-1/assets/theme.js?v=<?= filemtime(__DIR__ . '/assets/theme.js') ?>"></script>
  <link rel="icon" type="image/png" sizes="32x32" href="releases/yoma-design-20261111-1/assets/icon-32.png?v=20261112-anime">
  <link rel="apple-touch-icon" sizes="180x180" href="releases/yoma-design-20261111-1/assets/icon-180.png?v=20261112-anime">
  <link rel="shortcut icon" type="image/png" sizes="192x192" href="releases/yoma-design-20261111-1/assets/icon-192.png?v=20261112-anime">
  <link rel="icon" type="image/png" sizes="192x192" href="releases/yoma-design-20261111-1/assets/icon-192.png?v=20261112-anime">
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/app.css?v=<?= filemtime(
    __DIR__ . '/assets/app.css',
  ) ?>">
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/features.css?v=<?= filemtime(
    __DIR__ . '/assets/features.css',
  ) ?>">
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/medianoche.css?v=<?= filemtime(__DIR__ . '/assets/medianoche.css') ?>">
  <script src="releases/yoma-design-20261111-1/assets/bridge.js?v=<?= filemtime(
    __DIR__ . '/assets/bridge.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/catalog.js?v=<?= filemtime(
    __DIR__ . '/assets/catalog.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/radio.js?v=<?= filemtime(
    __DIR__ . '/assets/radio.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/radio-view.js?v=<?= filemtime(
    __DIR__ . '/assets/radio-view.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/bridge-ui.js?v=<?= filemtime(
    __DIR__ . '/assets/bridge-ui.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/downloads.js?v=<?= filemtime(
    __DIR__ . '/assets/downloads.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/transport.js?v=<?= filemtime(__DIR__.'/assets/transport.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/dom-renderer.js?v=<?= filemtime(__DIR__.'/assets/dom-renderer.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/health-ui.js?v=<?= filemtime(__DIR__.'/assets/health-ui.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/state-client.js?v=<?= filemtime(
    __DIR__ . '/assets/state-client.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/account-avatar.js?v=<?= filemtime(__DIR__.'/assets/account-avatar.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/queue-api.js?v=<?= filemtime(
    __DIR__ . '/assets/queue-api.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/library-view.js?v=<?= filemtime(
    __DIR__ . '/assets/library-view.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-layout.js?v=<?= filemtime(__DIR__.'/assets/player-layout.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/mobile-player.js?v=<?= filemtime(__DIR__.'/assets/mobile-player.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-shelves.js?v=<?= filemtime(__DIR__.'/assets/player-shelves.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-template.js?v=<?= filemtime(__DIR__.'/assets/player-template.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-view.js?v=<?= filemtime(__DIR__.'/assets/player-view.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-controller.js?v=<?= filemtime(
    __DIR__ . '/assets/player-controller.js',
  ) ?>" defer></script>
  <?php if (player_preview_url()): ?>
  <script src="__qa_player/relay.js" defer></script>
  <?php endif; ?>
  <script src="releases/yoma-design-20261111-1/assets/feature-ui.js?v=<?= filemtime(
    __DIR__ . '/assets/feature-ui.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/notification-panel.js?v=<?= filemtime(__DIR__ . '/assets/notification-panel.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/player-experience.js?v=<?= filemtime(__DIR__ . '/assets/player-experience.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/experience-ui.js?v=<?= filemtime(__DIR__ . '/assets/experience-ui.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/accessibility.js?v=<?= filemtime(__DIR__ . '/assets/accessibility.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/radio-library.js?v=<?= filemtime(__DIR__ . '/assets/radio-library.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/catalog-tools.js?v=<?= filemtime(__DIR__ . '/assets/catalog-tools.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/pwa.js?v=<?= filemtime(
    __DIR__ . '/assets/pwa.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/mal-ui.js?v=<?= filemtime(
    __DIR__ . '/assets/mal-ui.js',
  ) ?>" defer></script>
   <script src="releases/yoma-design-20261111-1/assets/library-transfer.js?v=<?= filemtime(__DIR__ . '/assets/library-transfer.js') ?>" defer></script>
   <script src="releases/yoma-design-20261111-1/assets/account.js?v=<?= filemtime(
    __DIR__ . '/assets/account.js',
  ) ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/sidebar.js?v=<?= filemtime(__DIR__ . '/assets/sidebar.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/personal-ui.js?v=<?= filemtime(__DIR__.'/assets/personal-ui.js') ?>" defer></script>
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/mobile-app.css?v=<?= filemtime(__DIR__.'/assets/mobile-app.css') ?>">
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/comfort.css?v=<?= filemtime(__DIR__.'/assets/comfort.css') ?>">
  <link rel="stylesheet" href="releases/yoma-design-20261111-1/assets/yoma.css?v=<?= filemtime(__DIR__.'/assets/yoma.css') ?>">
  <script src="releases/yoma-design-20261111-1/assets/choice-sheet.js?v=<?= filemtime(__DIR__.'/assets/choice-sheet.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/mobile-app.js?v=<?= filemtime(__DIR__.'/assets/mobile-app.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/app-downloads.js?v=<?= filemtime(__DIR__.'/assets/app-downloads.js') ?>" defer></script>
  <script src="releases/yoma-design-20261111-1/assets/app.js?v=<?= filemtime(
    __DIR__ . '/assets/app.js',
  ) ?>" defer></script>
</head>
<body>
<svg class="svg-library" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><defs>
  <symbol id="i-compass" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="m16 8-2.5 5.5L8 16l2.5-5.5Z"/></symbol>
  <symbol id="i-calendar" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 10h18m-13 4h2m4 0h2m-8 4h2"/></symbol>
  <symbol id="i-library" viewBox="0 0 24 24"><rect x="3" y="3" width="5" height="18" rx="1"/><rect x="10" y="3" width="5" height="18" rx="1"/><path d="m18 3 3 17-3 .6-3-17Z"/></symbol>
  <symbol id="i-download" viewBox="0 0 24 24"><path d="M12 3v12m-5-5 5 5 5-5M4 16v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/></symbol>
  <symbol id="i-history" viewBox="0 0 24 24"><path d="M3 11a9 9 0 1 1 2.7 7M3 4v7h7m2-4v5l3 2"/></symbol>
  <symbol id="i-settings" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/><circle cx="9" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="7" cy="18" r="2"/></symbol>
  <symbol id="i-search" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></symbol>
  <symbol id="i-star" viewBox="0 0 24 24"><path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/></symbol>
  <symbol id="i-arrow" viewBox="0 0 24 24"><path d="M4 12h16m-6-6 6 6-6 6"/></symbol>
  <symbol id="i-refresh" viewBox="0 0 24 24"><path d="M20 5v5h-5M4 19v-5h5m-4-5a8 8 0 0 1 13-5l2 2M4 18l2 2a8 8 0 0 0 13-5"/></symbol>
  <symbol id="i-check" viewBox="0 0 24 24"><path d="m5 12 4 4L19 6"/></symbol>
  <symbol id="i-close" viewBox="0 0 24 24"><path d="m6 6 12 12M6 18 18 6"/></symbol>
  <symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></symbol>
  <symbol id="i-menu" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/></symbol>
  <symbol id="i-sidebar-hide" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16m7-11-3 3 3 3"/></symbol>
  <symbol id="i-sidebar-show" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16m4-11 3 3-3 3"/></symbol>
  <symbol id="i-pc" viewBox="0 0 24 24"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8m-4-4v4"/></symbol>
  <symbol id="i-play" viewBox="0 0 24 24"><path d="m8 4 13 8-13 8Z"/></symbol>
  <symbol id="i-eye" viewBox="0 0 24 24"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></symbol>
  <symbol id="i-bell" viewBox="0 0 24 24"><path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5Zm5 3h4"/></symbol>
  <symbol id="i-upload" viewBox="0 0 24 24"><path d="M12 16V3m-5 5 5-5 5 5M4 16v5h16v-5"/></symbol>
  <symbol id="i-heart" viewBox="0 0 24 24"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0l-1 1-1-1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/></symbol>
  <symbol id="i-music" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13M9 9l12-2"/><ellipse cx="6" cy="18" rx="3" ry="3"/><ellipse cx="18" cy="16" rx="3" ry="3"/></symbol>
  <symbol id="i-pause" viewBox="0 0 24 24"><path d="M8 4v16M16 4v16" stroke-width="4"/></symbol>
  <symbol id="i-collapse" viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></symbol>
  <symbol id="i-expand" viewBox="0 0 24 24"><path d="m6 15 6-6 6 6"/></symbol>
<symbol id="i-bell" viewBox="0 0 24 24"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></symbol></defs></svg>
<a class="skip-content" href="#main">Saltar al contenido</a>
<div class="app-shell">
  <aside id="sidebar" class="navigation-menu" role="dialog" aria-modal="true" aria-labelledby="navigation-menu-title" hidden>
    <div class="navigation-menu-heading"><strong id="navigation-menu-title">Tu espacio</strong><button class="icon-button" data-action="menu" aria-label="Cerrar menú"><svg aria-hidden="true"><use href="#i-close"/></svg></button></div>
    <nav aria-label="Más secciones"><button class="nav-item" data-view="discover"><svg aria-hidden="true"><use href="#i-compass"/></svg><span>Catálogo</span></button><button class="nav-item" data-view="schedule"><svg aria-hidden="true"><use href="#i-calendar"/></svg><span>Temporada</span></button><button class="nav-item" data-view="radio"><svg aria-hidden="true"><use href="#i-music"/></svg><span>Radio</span></button><button class="nav-item" data-view="library"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Mi biblioteca</span></button><button class="nav-item" data-view="mal"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Mi lista MAL</span></button><button class="nav-item" data-view="favorites"><svg aria-hidden="true"><use href="#i-star"/></svg><span>Favoritos</span></button><button class="nav-item" data-view="collections"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Colecciones</span></button><button class="nav-item" data-view="sync"><svg aria-hidden="true"><use href="#i-refresh"/></svg><span>Sincronización MAL</span></button><button class="nav-item" data-view="queue"><svg aria-hidden="true"><use href="#i-download"/></svg><span>Cola para la PC</span><span id="queue-badge" class="nav-count">0</span></button><button class="nav-item" data-view="history"><svg aria-hidden="true"><use href="#i-history"/></svg><span>Actividad</span></button><button class="nav-item" data-view="stats"><svg aria-hidden="true"><use href="#i-history"/></svg><span>Estadísticas</span></button><button class="nav-item" data-view="settings"><svg aria-hidden="true"><use href="#i-settings"/></svg><span>Preferencias</span></button></nav>
    <button class="pc-card" data-action="help"><span class="pc-icon"><svg aria-hidden="true"><use href="#i-pc"/></svg></span><strong>De la web a tu PC</strong><span>Prepara tus capítulos y descárgalos con YomaTV.</span><span class="pc-link">Cómo funciona <svg aria-hidden="true"><use href="#i-arrow"/></svg></span></button>
  </aside>
  <button id="sidebar-backdrop" class="navigation-backdrop" data-action="menu" aria-label="Cerrar menú" tabindex="-1" hidden></button>
  <div class="workspace">
    <nav class="yoma-sections" aria-label="Yoma"><a href="https://yoma.site/">‹ Yoma</a><a class="to-manga" href="https://shi.yoma.site/">Ir a YomaShi</a></nav>
    <header class="site-header"><div class="header-inner">
      <a class="brand" href="#discover" aria-label="YomaTV · Inicio"><img src="releases/yoma-design-20261111-1/assets/yoma-anime.png?v=1" alt="" width="40" height="40"><span>Yoma<span class="brand-accent">TV</span></span></a>
      <nav class="desktop-navigation" aria-label="Navegación principal"><button class="nav-item" data-view="discover"><svg aria-hidden="true"><use href="#i-compass"/></svg><span>Catálogo</span></button><button class="nav-item" data-view="schedule"><svg aria-hidden="true"><use href="#i-calendar"/></svg><span>Temporada</span></button><button class="nav-item" data-view="radio"><svg aria-hidden="true"><use href="#i-music"/></svg><span>Radio</span></button><button class="nav-item" data-view="library"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Mi biblioteca</span></button><button class="nav-item" data-view="mal"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Mi lista MAL</span></button></nav>
      <div class="header-utilities"><button id="bridge-indicator" class="connection-pill" data-action="connect" aria-label="Conexión con YomaTV"><span class="connection-dot unpaired"></span><span>Sin emparejar</span></button><button id="notifications-toggle" class="notification-button icon-button" data-action="notifications_toggle" aria-label="Capítulos nuevos" aria-haspopup="dialog" aria-controls="notification-panel" aria-expanded="false"><svg aria-hidden="true"><use href="#i-bell"/></svg><span id="notification-badge">0</span></button><button class="account-button" id="account" data-action="account" aria-label="Mi cuenta"><span class="avatar">S</span><span>Mi cuenta</span></button><button id="sidebar-toggle" class="icon-button" data-action="menu" aria-label="Más secciones" title="Más secciones" aria-controls="sidebar" aria-expanded="false"><svg aria-hidden="true"><use href="#i-menu"/></svg></button></div>
    </div></header>
    <div class="page-context"><span id="breadcrumb">Catálogo completo</span><span id="season-label" class="season-chip">Temporada</span></div>
    <nav class="mobile-navigation" aria-label="Navegación móvil"><button class="nav-item" data-view="discover"><svg aria-hidden="true"><use href="#i-compass"/></svg><span>Catálogo</span></button><button class="nav-item" data-view="schedule"><svg aria-hidden="true"><use href="#i-calendar"/></svg><span>Temporada</span></button><button class="nav-item" data-view="radio"><svg aria-hidden="true"><use href="#i-music"/></svg><span>Radio</span></button><button class="nav-item" data-view="library"><svg aria-hidden="true"><use href="#i-library"/></svg><span>Biblioteca</span></button><button class="nav-item" data-action="menu" aria-label="Más secciones"><svg aria-hidden="true"><use href="#i-menu"/></svg><span>Más</span></button></nav>
    <section id="notification-panel" class="notification-panel" role="dialog" aria-modal="false" aria-labelledby="notification-panel-heading" tabindex="-1" hidden><header class="notice-header"><h2 id="notification-panel-heading">Notificaciones</h2><button type="button" class="text-button" data-notice-action="read" disabled>Marcar todas leídas</button><button type="button" class="icon-button" data-notice-action="close" aria-label="Cerrar notificaciones"><svg aria-hidden="true"><use href="#i-close"/></svg></button></header><div class="notice-content" data-notice-content></div><footer><button class="text-button" data-view="notifications">Ver todas las notificaciones <span aria-hidden="true">→</span></button></footer></section>
    <main id="main" tabindex="-1"><div class="loading-view"><span class="spinner"></span><p>Preparando tu temporada…</p></div></main>
    <aside id="radio-dock" class="radio-dock" aria-label="Reproductor de radio YouTube" hidden></aside>
    <footer class="footer"><span>YomaTV <span class="muted">· Hecho para tus temporadas.</span></span><span>Catálogo público de <a href="https://animeav1.com/catalogo" target="_blank" rel="noopener noreferrer">AnimeAV1 ↗</a></span></footer>
  </div>
</div>
<dialog id="dialog" class="dialog"><button class="dialog-close icon-button" data-action="close" aria-label="Cerrar"><svg><use href="#i-close"/></svg></button><div id="dialog-body"></div></dialog>
<div id="toast" class="toast" role="status" aria-live="polite"></div>
<input type="file" id="receipt-file" accept="application/json,.json" multiple hidden>
<noscript><p>Activa JavaScript para usar tu biblioteca, el horario y las colas de YomaTV.</p></noscript>
</body>
</html>
