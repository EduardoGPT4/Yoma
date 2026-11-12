'use strict';
let featureHome = null,
  malLibraryPage = null,
  statsPage = null,
  noticesPage = null,
  xmlPreview = null,
  malRefreshBusy = false,
  featureLoading = false;
const malFilters = { status: '', search: '', page: 1 };
let noticesUpTo=0, noticesHasMore=false, noticesLoading=false, noticeSequence=0;
let featureTimer,
  featureUser = 0,
  playerView = null,
  featureSequence = 0,
  maintenanceBusy = false,
  playerController = null,
  watchPumpTimer = null,
  watchPumpBusy = false;
function resetFeatures() {
  globalThis.SeasonNotifications?.reset();
  if (typeof leavePlayerPage==='function') leavePlayerPage();
  playerController?.destroy();
  playerController = null;
  clearTimeout(watchPumpTimer);
  watchPumpTimer = null;
  watchPumpBusy = false;
  featureHome = null;
  malLibraryPage = null;
  statsPage = null;
  noticesPage = null;
  noticesUpTo=0;noticesHasMore=false;noticesLoading=false;noticeSequence++;
  xmlPreview = null;
  playerView = null;
  featureLoading = false;
  malRefreshBusy = false;
  featureSequence++;
  malLibrarySequence++;
  malDialogRequest++;
}
function acceptFeatureResult(result) {
  const user = Number(state?.user?.id || 0);
  if (
    result.home &&
    Number(result.home.user_id) === user &&
    (!featureHome || result.home.revision >= featureHome.revision)
  ) {
    const oldCount = featureHome?.notifications;
    const oldNoticeRevision=featureHome?.notifications_revision;
    featureHome = result.home;
    if ((oldNoticeRevision!==undefined && Number(featureHome.notifications_revision)>Number(oldNoticeRevision)) || (oldCount !== undefined && featureHome.notifications > oldCount)) {
      noticesPage = null;
      noticesLoading=false;noticeSequence++;
      try {
        if (
          'Notification' in window &&
          Notification.permission === 'granted' &&
          localStorage.getItem('seasonav1.notice') === 'yes'
        ) {
          const notice = new Notification('YomaTV · Capítulos nuevos', {
            body: `Tienes ${featureHome.notifications} avisos pendientes de tus animes seguidos.`,
            icon: 'releases/yoma-design-20261111-1/assets/icon-192.png?v=20261015-human-v3',
            tag: 'seasonav1-new-episodes',
          });
          notice.onclick = () => {
            window.focus();
            navigate('notifications');
          };
        }
      } catch {}
    }
  }
  updateFeatureHeader();
  scheduleWatchPump();
}
function scheduleWatchPump() {
  clearTimeout(watchPumpTimer);
  watchPumpTimer = null;
  const pending = featureHome?.watch_pending;
  if (
    watchPumpBusy ||
    document.hidden ||
    !state?.user ||
    !featureHome?.mal.connected ||
    !pending?.count
  )
    return;
  const delay = Math.max(
    750,
    Number(pending.next_retry || 0) * 1000 - Date.now()
  );
  watchPumpTimer = setTimeout(async () => {
    watchPumpTimer = null;
    watchPumpBusy = true;
    const user = state.user?.id,
      seq = featureSequence;
    try {
      const r = await api('watch_retry');
      if (seq !== featureSequence || user !== state.user?.id) return;
      statsPage = null;
      malLibraryPage = null;
      if (
        playerView?.episode.slug === r.watch_sync?.slug &&
        (playerController?.thresholdSent ||
          Number(r.watch_sync.target) === Number(playerView.episode.number))
      ) {
        const node = document.querySelector('[data-player-watch-status]');
        if (node) {
          node.textContent = r.watch_sync.message;
          node.dataset.state = r.watch_sync.state;
          updatePlayerWatchBadge(r.watch_sync.state);
          acceptPlayerMark(playerView,r.watch_sync);
          if (r.watch_sync.state === 'synced') playerController?.notifySynced();
        }
      }
    } catch {
      // Back off on a site/network error. It never represents watched time.
      if (seq === featureSequence && featureHome?.watch_pending)
        featureHome.watch_pending.next_retry =
          Math.floor(Date.now() / 1000) + 60;
    } finally {
      if (seq === featureSequence) {
        watchPumpBusy = false;
        scheduleWatchPump();
      }
    }
  }, delay);
}
function playerExtensionHelp() {
  modal(
    `<div class="auth-form"><p class="eyebrow">YOMATV + BRAVE</p><h2>Detección real del capítulo visto.</h2><p>Instala o actualiza la extensión 1.2 para conectar la posición de MP4Upload con YomaTV. No lee contraseñas ni tu cuenta de MAL.</p><ol class="extension-steps"><li><a href="releases/yoma-design-20261111-1/downloads/YomaTV-Brave.zip" class="button primary">Descargar extensión para Brave</a> y extrae el ZIP en una carpeta que conservarás.</li><li>Abre <code>brave://extensions</code> y activa «Modo de desarrollador».</li><li>Pulsa «Cargar descomprimida» y elige la carpeta extraída que contiene <code>manifest.json</code>.</li><li>Si ya la tenías instalada, reemplaza sus archivos por los del ZIP y pulsa «Recargar» en su tarjeta de <code>brave://extensions</code>. Después recarga YomaTV y abre el capítulo. Verás «Detección activa» cuando se conecte.</li></ol><p>Al alcanzar el 80 % de la posición del video se guarda en la web y en MAL. También funciona al adelantar. Conecta MAL y vincula la ficha correcta para enviar su progreso.</p><p class="muted">Atajos: Espacio pausa, ← / → saltan 10 s, F activa pantalla completa y M silencia. «Saltar intro» adelanta 85 s desde la posición actual. La ventana flotante se abre con el icono en la esquina superior derecha del video. Solo funciona con MP4Upload en esta web. Voe conserva sus controles, sin detección automática en esta versión.</p></div>`
  );
}
function updateFeatureHeader() {
  const badge = document.querySelector('#notification-badge');
  if (badge) { badge.textContent = featureHome?.notifications || 0; badge.hidden = !Number(featureHome?.notifications); }
  globalThis.SeasonNotifications?.sync();
  document.querySelectorAll('[data-countdown]').forEach((node) => {
    const seconds = Math.max(
      0,
      Number(node.dataset.countdown) - Date.now() / 1000
    );
    const days = Math.floor(seconds / 86400),
      hours = Math.floor((seconds % 86400) / 3600);
    node.textContent = seconds
      ? `Próximo: ${days ? days + 'd ' : ''}${hours}h · estimado`
      : 'Pendiente de actualización';
  });
}
async function loadFeatureHome(auto = true) {
  if (featureLoading) return;
  featureLoading = true;
  const user = Number(state?.user?.id || 0),
    seq = featureSequence;
  try {
    await api('home', {}, true);
    if (seq !== featureSequence || user !== Number(state?.user?.id || 0))
      return;
    if (view === 'discover' || view === 'notifications') renderFeaturePage();
    if (
      auto &&
      featureHome?.mal.connected &&
      featureHome.mal_synced_at < Date.now() / 1000 - 21600
    )
      refreshMal(false).catch((error) => toast(error.message, true));
    if (
      (auto || (featureHome?.maintenance?.remaining || featureHome?.maintenance?.catalog_due)) &&
      state.user?.is_admin &&
      featureHome?.maintenance &&
      (featureHome.maintenance.next_due <= Date.now() / 1000 ||
        featureHome.maintenance.remaining || featureHome.maintenance.catalog_due)
    )
      maintainSite().catch((error) => toast(error.message, true));
  } finally {
    featureLoading = false;
  }
}
async function maintainSite() {
  if (maintenanceBusy || !state.user?.is_admin) return;
  maintenanceBusy = true;
  const user = state.user.id,
    seq = featureSequence;
  try {
    let steps=0;
    do {
      if (++steps>20) break;
      if (
        document.hidden ||
        view === 'watch' ||
        $('#dialog').open ||
        state.user?.id !== user ||
        seq !== featureSequence
      )
        return;
      const result = await api('maintenance');
      if (state.user?.id !== user || seq !== featureSequence) return;
      if (view === 'schedule' || view === 'discover' || view === 'settings')
        renderFeaturePage();
      if (
        result.maintenance_result.skipped ||
        (!result.maintenance_result.remaining && !result.maintenance_result.catalog_pending)
      )
        break;
      await new Promise((resolve) => setTimeout(resolve, 2200));
    } while (true);
  } finally {
    maintenanceBusy = false;
  }
}
function renderFeaturePage() {
  const active = document.activeElement,
    id = active?.id,
    start = active?.selectionStart;
  render();
  if (id && active?.tagName === 'INPUT') {
    const next = document.getElementById(id);
    if (next) {
      next.focus();
      if (start !== null && next.type === 'search')
        next.setSelectionRange(start, start);
    }
  }
}
async function refreshMal(notify = true) {
  if (malRefreshBusy || !state.user) return;
  malRefreshBusy = true;
  const user = state.user.id,
    seq = featureSequence;
  let offset = 0,
    count = 0;
  try {
    do {
      const result = await api('mal_refresh', { offset });
      if (seq !== featureSequence || state.user?.id !== user) return;
      count += result.progress.received;
      offset = result.progress.offset;
      const target = document.querySelector('[data-mal-progress]');
      if (target) target.textContent = `Actualizando MAL… ${count} animes`;
      if (view === 'discover') renderFeaturePage();
      if (!result.progress.more) break;
      await new Promise((resolve) => setTimeout(resolve, 1200));
    } while (offset);
    malLibraryPage = null;
    if (view === 'mal') await loadMalLibrary();
    else if (view === 'discover') await loadCatalog();
    if (notify) toast(`Lista de MAL actualizada: ${count} animes.`);
  } finally {
    if (seq === featureSequence) malRefreshBusy = false;
    const node = document.querySelector('[data-mal-progress]');
    if (node) node.textContent = '';
  }
}
function malTile(m) {
  const poster = m.cover || (m.slug ? lookupAnime(m.slug)?.cover : '');
  const id = Number(m.mal_id),
    source = m.slug ? `data-open="${e(m.slug)}"` : `data-mal-edit="${id}"`;
  return `<article class="anime-card mal-card"><button class="poster mal-poster" ${source} aria-label="Abrir ${e(m.title)}">${poster ? `<img src="${e(poster)}" alt="Portada de ${e(m.title)}" loading="lazy">` : '<span class="mal-cover-placeholder">MAL</span>'}<span class="episode-badge">${e(MAL_STATUSES[m.status] || 'Por ver')}</span><span class="card-status">${m.source === 'xml' ? 'XML' : 'MAL'}</span></button><button class="mal-title" ${source}><h3 class="card-title">${e(m.title)}</h3></button><div class="watch-progress mal-card-progress" role="progressbar" aria-label="Progreso de episodios" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${m.num_episodes?Math.min(100,Math.round((Number(m.watched)||0)/Number(m.num_episodes)*100)):0}"><span style="width:${m.num_episodes?Math.min(100,(Number(m.watched)||0)/Number(m.num_episodes)*100):0}%"></span></div><span class="mal-home-meta">${Number(m.watched)||0}${m.num_episodes?' de '+Number(m.num_episodes)+' episodios':' vistos'}</span><div class="card-meta mal-full-meta">${Number(m.watched) || 0}${m.num_episodes ? ` / ${Number(m.num_episodes)}` : ''} capítulos vistos · ${Number(m.score) ? Number(m.score) + '/10' : 'Sin nota'}</div><div class="mal-card-actions"><button class="text-button" data-mal-edit="${id}">Editar en MAL</button><button class="text-button" data-mal-match="${id}">${m.slug ? 'Revisar vínculo' : 'Vincular AnimeAV1'}</button></div></article>`;
}
function detailDownloadCounts(episodes) {
  const states = episodes.map(episodeDownload);
  return {done:states.filter(s => s.phase === 'confirmed').length,
    queued:states.filter(s => ['queued','paused','downloading','verifying'].includes(s.phase)).length};
}
function updateDetailProgressDownloads(episodes) {
  const node=document.querySelector('[data-detail-download-count]');if(!node)return;
  const {done,queued}=detailDownloadCounts(episodes);
  node.textContent=done;
  document.querySelector('[data-detail-download-label]').textContent=done===1?'guardado':'guardados';
  document.querySelector('[data-detail-queued-count]').textContent=queued+' en cola';
}
function detailProgressCards(a, episodes) {
  const seen = episodes.filter(ep => ep.watched).length;
  const {done,queued} = detailDownloadCounts(episodes);
  const mal = a.mal || lookupAnime(a.slug)?.mal;
  return `<section class="detail-progress" aria-label="Tu progreso en este anime"><article><h3>Tu avance</h3><strong>${seen} <small>de ${episodes.length} vistos</small></strong><div class="watch-progress" role="progressbar" aria-label="Capítulos vistos" aria-valuemin="0" aria-valuemax="${Math.max(1,episodes.length)}" aria-valuenow="${seen}"><span style="width:${seen/Math.max(1,episodes.length)*100}%"></span></div></article><article><h3>En tu PC</h3><strong class="confirmed"><span data-detail-download-count>${done}</span> <small data-detail-download-label>${done===1?'guardado':'guardados'}</small></strong><p class="queued" data-detail-queued-count>${queued} en cola</p></article><article><h3>MyAnimeList</h3><strong>${mal ? e(MAL_STATUSES[mal.status] || 'Vinculado') : '—'}</strong><p>${mal ? `${Number(mal.watched)||0} vistos en MAL` : 'Conecta tu lista'}</p>${state.user ? mal ? `<button class="text-button" data-mal-edit="${Number(mal.id)}" aria-label="Editar en MyAnimeList">Editar →</button>` : button('mal_find','Vincular','','data-slug="'+e(a.slug)+'" aria-label="Vincular con MyAnimeList"','small ghost') : '<button class="text-button" data-action="account">Conectar →</button>'}</article></section>`;
}
function catalogMetadataInfo(a) {
  const values = [...(a.genres || []).slice(0,3)];
  if (a.mal_mean) values.push('★ ' + Number(a.mal_mean).toFixed(1) + '/10 en MAL');
  return values.length ? `<p class="catalog-metadata">${values.map(e).join(' · ')}</p>` : '';
}
function catalogMetadataExtra(a) {
  return (a.genres?.length||a.studios?.length)?`<details class="detail-fold"><summary>Ficha del anime</summary>${a.genres?.length?`<p>Géneros: ${a.genres.map(e).join(' · ')}</p>`:''}${a.studios?.length?`<p>Estudio: ${a.studios.map(e).join(', ')}</p>`:''}</details>`:'';
}
function catalogPersonalSections() {
  if (!featureHome) return '';
  const h = featureHome,native=typeof yomaNative==='function'&&yomaNative();
  let out = h.continue.length
    ? `<section class="personal-section"><div class="section-heading"><h2>${native?'Continúa viendo':'Continúa donde lo dejaste'}</h2><button class="text-button" data-view="library">Ver mi biblioteca →</button></div><div class="continue-grid">${h.continue.map((a) => `<article class="continue-card"><img src="${e(a.cover)}" alt="" loading="lazy"><div><strong>${e(a.title)}</strong><span>Capítulo ${e(a.number)}${a.position?' · '+positionText(a.position)+' / '+positionText(a.duration):''}</span><div class="watch-progress" role="progressbar" aria-label="Progreso de reproducción" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(Math.min(100,Math.max(0,Number(a.position)||0)/Math.max(1,Number(a.duration)||1)*100))}"><span style="width:${Math.min(100,Math.max(0,Number(a.position)||0)/Math.max(1,Number(a.duration)||1)*100)}%"></span></div></div><button class="continue-play icon-button" data-play="${a.episode_id}" aria-label="Continuar ${e(a.title)}">${icon('play')}</button></article>`).join('')}</div></section>`
    : '';
  if (h.total) {
    out += `<section class="personal-section"><div class="section-heading"><div><p class="eyebrow">TU LISTA DE MYANIMELIST</p><h2>${native?'Tu lista de MyAnimeList':'Las historias que estás siguiendo.'}</h2></div><button class="button ghost" data-view="mal">${native?'Ver todo →':'Ver mi lista completa'}</button></div><p class="muted" data-mal-progress>${malRefreshBusy ? 'Actualizando MAL…' : h.unmatched ? `${h.unmatched} ${h.unmatched === 1 ? 'anime pendiente' : 'animes pendientes'} de vincular con AnimeAV1.` : 'Tus coincidencias están vinculadas.'}</p>`;
    for (const [key, label, count] of [
      ['watching', 'Viendo', h.watching_count],
      ['planned', 'Por ver', h.planned_count],
    ])
      if (h[key].length)
        out += `<div class="section-heading"><h3>${label} <span class="muted">(${count})</span></h3><button class="text-button" data-mal-filter="${key === 'planned' ? 'plan_to_watch' : key}">Ver todos</button></div><div class="card-grid personal-cards">${h[key].slice(0, 8).map(malTile).join('')}</div>`;
    out += '</section>';
  } else if (state.user)
    out += `<section class="note-banner"><span class="mal-logo">MAL</span><div><strong>Tu lista también tiene un lugar aquí.</strong><p>Conecta MyAnimeList o importa su XML para mostrar tus animes en «Viendo» y «Por ver».</p></div><button class="button ghost" data-view="mal">Abrir mi lista MAL</button></section>`;
  return out;
}
function malLibraryView() {
  const heading = title(
    'MYANIMELIST',
    'Tu lista, dentro de tu catálogo.',
    'Edita en MAL, vincula las fichas y conserva el progreso.',
    `<div class="toolbar"><button class="button ghost" data-exp="batch">Revisar coincidencias</button>${button('mal_refresh_all', 'Actualizar MAL', 'refresh', '', 'ghost')}${button('mal_xml_open', 'Importar XML', 'upload', '', 'primary')}</div>`
  );
  if (!state.user)
    return (
      heading +
      empty(
        'Inicia sesión para abrir tu lista',
        'Los datos de MAL pertenecen a tu cuenta.',
        button('account', 'Iniciar sesión', '', '', 'primary')
      )
    );
  if (!malLibraryPage) {
    loadMalLibrary().catch((error) => toast(error.message, true));
    return heading + '<p class="muted">Cargando tu lista…</p>';
  }
  const p = malLibraryPage;
  return (
    heading +
    `<div class="filter-bar"><input id="mal-search" class="form-input" type="search" aria-label="Buscar en mi lista MAL" placeholder="Buscar en tu lista…" value="${e(malFilters.search)}"><select id="mal-status" class="select-input" aria-label="Estado en MAL"><option value="">Todos los estados</option>${Object.entries(
      MAL_STATUSES
    )
      .filter(([key]) => key !== 'unknown')
      .map(
        ([key, label]) =>
          `<option value="${key}" ${malFilters.status === key ? 'selected' : ''}>${label}</option>`
      )
      .join(
        ''
      )}</select></div><p class="muted" data-mal-progress>${malRefreshBusy ? 'Actualizando MAL…' : `${p.total} animes · página ${p.page} de ${p.pages}`}</p>${!featureHome?.mal.connected ? '<div class="note-banner"><p>La edición remota requiere conectar MyAnimeList desde Mi cuenta. El XML y las relaciones guardadas se pueden consultar sin conexión a MAL.</p><button class="button ghost" data-view="account">Conectar MAL</button></div>' : ''}${p.items.length ? `<div class="card-grid">${p.items.map(malTile).join('')}</div>` : empty('Tu lista está por llegar', 'Actualiza desde MAL o importa el XML de exportación.')}<div class="catalog-pagination">${button('mal_page_prev', 'Anterior', '', p.page <= 1 ? 'disabled' : '', 'ghost')}<span>${p.page} / ${p.pages}</span>${button('mal_page_next', 'Siguiente', '', p.page >= p.pages ? 'disabled' : '', 'ghost')}</div><input id="mal-xml-file" type="file" accept=".xml,text/xml,application/xml" hidden>`
  );
}
let malLibraryLoading = false;
let malLibrarySequence = 0, malDialogRequest = 0;
async function loadMalLibrary() {
  if (!state.user) return;
  malLibraryLoading = true;
  const user = state.user.id, sequence = ++malLibrarySequence, filters = { ...malFilters };
  try {
    const r = await api('mal_cached', filters, true);
    if (state.user?.id !== user || sequence !== malLibrarySequence || JSON.stringify(filters) !== JSON.stringify(malFilters)) return;
    malLibraryPage = r.mal_library;
    if (view === 'mal') renderFeaturePage();
  } finally {
    if (sequence === malLibrarySequence) malLibraryLoading = false;
  }
}
async function editMal(id) {
  const interaction = dialogTicket(), request = ++malDialogRequest;
  const user = state.user?.id,
    seq = featureSequence;
  const r = await api('mal_entry', { mal_id: id }, true),
    m = r.mal_entry;
  if (user !== state.user?.id || seq !== featureSequence || request !== malDialogRequest || !dialogCurrent(interaction)) return;
  modal(
    `<div class="auth-form"><p class="eyebrow">EDITAR EN MYANIMELIST</p><h2>${e(m.title)}</h2><p>Al guardar se actualizará tu lista real de MAL. Si reduces los capítulos vistos, se cancelarán los envíos pendientes y las marcas web superiores. Los reproductores abiertos antes de la corrección tendrán que reabrirse.</p><form id="mal-edit-form" data-watched="${Number(m.watched)||0}" data-id="${id}" data-account="${Number(m.mal_account_id) || 0}"><label>Estado<select name="status" class="select-input">${Object.entries(
      MAL_STATUSES
    )
      .filter(([k]) => k !== 'unknown')
      .map(
        ([k, v]) =>
          `<option value="${k}" ${(m.status || 'plan_to_watch') === k ? 'selected' : ''}>${e(v)}</option>`
      )
      .join(
        ''
      )}</select></label><label>Capítulos vistos<input name="watched" class="form-input" type="number" min="0" max="${Number(m.num_episodes) || 100000}" value="${Number(m.watched) || 0}" required></label><label><input type="checkbox" name="correct_progress"> Corregir también las marcas web y cancelar envíos de progreso pendientes</label><label>Puntuación<select class="select-input" name="score">${Array.from({ length: 11 }, (_, n) => `<option value="${n}" ${Number(m.score) === n ? 'selected' : ''}>${n ? n + '/10' : 'Sin nota'}</option>`).join('')}</select></label><p class="form-error" aria-live="polite"></p><button class="button primary" type="submit" ${!featureHome?.mal.connected ? 'disabled' : ''}>Guardar en MyAnimeList</button></form><div class="mal-edit-footer">${m.status ? button('mal_remove_prompt', 'Retirar de mi lista de MAL', 'close', `data-id="${id}" data-account="${Number(m.mal_account_id) || 0}"`, 'ghost') : ''}${m.notes ? `<p class="muted">Notas guardadas en la web: ${e(m.notes)}</p>` : ''}<p class="muted">Los capítulos descargados en tu PC se conservan.</p></div></div>`
  );
}
async function matchMal(id, search = '') {
  const interaction = dialogTicket(), request = ++malDialogRequest;
  const user = state.user?.id,
    seq = featureSequence;
  const r = await api('mal_candidates', { mal_id: id, search }),
    m = r.mal_anime;
  if (user !== state.user?.id || seq !== featureSequence || request !== malDialogRequest || !dialogCurrent(interaction)) return;
  modal(
    `<p class="eyebrow">VINCULAR CON ANIMEAV1</p><h2>${e(m.title)}</h2><p class="muted">MyAnimeList #${id} · ${e(m.media_type)} · ${e(m.start_date || 'Fecha sin datos')}</p><p>Elige la ficha que corresponde a este anime de MAL. Comprueba la temporada y el formato.</p><form id="mal-match-search" data-id="${id}" class="toolbar"><input name="search" class="form-input" placeholder="Buscar otro título de AnimeAV1…" value="${e(search)}" required><button class="button ghost" type="submit">Buscar</button></form><div class="match-results">${r.matches.map((a) => `<article class="match-row"><img src="${e(a.cover)}" alt="" loading="lazy"><div><strong>${e(a.title)}</strong><span>${e(a.category)} · ${e(a.start_date || 'Fecha sin datos')} · similitud ${a.match_score}%</span></div><button class="button small primary" data-action="mal_choose" data-id="${id}" data-slug="${e(a.slug)}">Vincular esta ficha</button></article>`).join('') || '<p>No hay coincidencias. Prueba otro nombre; puedes consultar la lista de MAL aunque el anime no esté en AnimeAV1.</p>'}</div>${button('mal_unlink', 'Quitar vínculo guardado', 'close', `data-id="${id}"`, 'ghost')}`
  );
}
function sourceMalPanel(a) {
  return `<div class="detail-mal-toolbar"><span class="mal-logo">MAL</span><div><strong>${a.mal ? `Vinculado · ${e(MAL_STATUSES[a.mal.status] || 'Sin añadir a MAL')}` : 'Relaciona esta ficha con MyAnimeList'}</strong><span>${a.mal ? `${a.mal.watched} capítulos vistos · ${a.mal.score ? a.mal.score + '/10' : 'Sin nota'}` : 'Puedes elegir el título y la temporada correctos.'}</span></div>${a.mal ? `<button class="button small ghost" data-mal-edit="${a.mal.id}">Editar en MAL</button><button class="button small ghost" data-exp="reconcile" data-slug="${e(a.slug)}">Revisar mi avance</button>` : button('mal_find', 'Buscar en MAL', 'search', `data-slug="${e(a.slug)}"`, 'small ghost')}</div>`;
}
function showMalFind(slug) {
  const a = lookupAnime(slug);
  modal(
    `<p class="eyebrow">ELEGIR FICHA DE MAL</p><h2>${e(a?.title || slug)}</h2><p>Busca en MAL y elige el anime y la temporada correctos.</p><form id="mal-find-form" data-slug="${e(slug)}" class="toolbar"><input name="query" class="form-input" value="${e(a?.title || slug)}" minlength="3" maxlength="80" required><button class="button primary" type="submit">Buscar en MAL</button></form><div id="mal-find-results"></div>`
  );
}
function themeControls() {
  return `<section class="panel appearance-panel"><h2 class="panel-title">Apariencia</h2><label>Densidad<select class="select-input" id="appearance-density"><option value="compact" ${themePreferences.density==='compact'?'selected':''}>Compacta</option><option value="normal" ${themePreferences.density==='normal'?'selected':''}>Normal</option></select></label><div class="field-pair"><label>Tema<select id="appearance-theme" class="select-input">${[
    ['dark', 'Medianoche'],
    ['light', 'Papel claro'],
    ['system', 'Según el sistema'],
  ]
    .map(
      ([v, t]) =>
        `<option value="${v}" ${themePreferences.theme === v ? 'selected' : ''}>${t}</option>`
    )
    .join(
      ''
    )}</select></label><div class="appearance-palette"><span class="palette-dot"></span><strong>Medianoche</strong><span>Bermellón · tinta · papel</span></div></div><p class="muted">Se aplica al instante y se guarda en este navegador.</p><div class="toolbar"><a class="button ghost" href="releases/yoma-design-20261111-1/offline.html">Ver catálogo sin conexión</a>${button('pwa_install', 'Instalar aplicación web', 'pc', '', 'ghost')}${button('browser_notifications', 'Activar avisos con la web abierta', 'check', '', 'ghost')}</div></section>`;
}
function statisticsView() {
  if (!state.user)
    return empty(
      'Inicia sesión para ver tus estadísticas',
      'Tu progreso es privado.',
      button('account', 'Iniciar sesión')
    );
  if (!statsPage) {
    api('stats', {}, true)
      .then((r) => {
        statsPage = r.stats;
        if (view === 'stats') render();
      })
      .catch((err) => toast(err.message, true));
    return '<p>Cargando estadísticas…</p>';
  }
  const s = statsPage;
  return (
    title(
      'TU RECORRIDO',
      'Las historias también cuentan.',
      'Progreso de MAL y la web sin duplicar los animes vinculados.'
    ) +
    `<div class="feature-stats">${[
      [s.watched, 'Capítulos vistos'],
      [s.estimated_hours, 'Horas estimadas'],
      [(s.download_bytes / 1073741824).toFixed(2), 'GB verificados por tu PC'],
      [s.downloaded, 'Descargas confirmadas'],
    ]
      .map(
        ([n, t]) =>
          `<article class="panel"><strong>${e(n)}</strong><span>${e(t)}</span></article>`
      )
      .join(
        ''
      )}</div><section class="panel"><h2>Puntuación media por temporada</h2>${s.season_scores.map((r) => `<div class="score-row"><span>${e(r.season)} · ${r.rated} ${r.rated === 1 ? 'anime' : 'animes'}</span><strong>${r.average}/10</strong><progress max="10" value="${r.average}"></progress></div>`).join('') || '<p class="muted">Puntúa tus animes para ver las medias.</p>'}<p class="muted">Las horas usan la duración de MAL cuando existe; en los demás casos se estiman 24 minutos por capítulo.</p></section>`
  );
}
function notificationsView() {
  if (!state.user)
    return empty(
      'Inicia sesión para consultar los avisos',
      'Los capítulos nuevos de tus animes seguidos aparecerán aquí.',
      button('account', 'Iniciar sesión')
    );
  if (!noticesPage) {
    if(noticesLoading) return '<p>Cargando notificaciones…</p>';
    noticesLoading=true;
    const user=state.user.id, sequence=featureSequence, request=++noticeSequence;
    api('notifications', {}, true)
      .then((r) => {
        if(user!==state.user?.id||sequence!==featureSequence||request!==noticeSequence) return;
        noticesHasMore=r.notifications.length===50;
        noticesPage = r.notifications;
        noticesUpTo = Number(r.notifications_up_to)||0;
        if (view === 'notifications') render();
      })
      .catch((err) => {if(request===noticeSequence)toast(err.message, true);})
      .finally(()=>{if(request===noticeSequence)noticesLoading=false;});
    return '<p>Cargando notificaciones…</p>';
  }
  return (
    title(
      'CAPÍTULOS NUEVOS',
      'Tus estrenos, a mano.',
      'Avisos de tus animes seguidos y favoritos.',
      button(
        'notifications_read',
        'Marcar todos como leídos',
        'check',
        '',
        'ghost'
      )
    ) +
    `<div class="notification-list">${noticesPage.map((n) => `<article class="notification-row ${Number(n.unread) ? 'unread' : ''}"><img src="${e(n.cover)}" alt="" loading="lazy"><div><strong>${e(n.title)}</strong><span>${Number(n.episode_count)>1?`${Number(n.episode_count)} capítulos · del ${Number(n.first_number)} al ${Number(n.number)}`:`Capítulo ${Number(n.number)}`} · ${Number(n.unread)||0} sin leer · ${e(dateText(Number(n.created_at)))}</span></div><button class="button ghost" data-open="${e(n.slug)}">Abrir anime</button></article>`).join('') || empty('Todavía no hay avisos', 'Recibirás avisos al detectar capítulos nuevos después de seguir un anime.')}</div>${noticesHasMore?button('notices_more','Cargar más animes','arrow','','ghost'):''}`
  );
}
function adminPanel() {
  const m = featureHome?.maintenance;
  return state.user?.is_admin
    ? `<section class="panel maintenance-panel"><h2>Actualización del sitio</h2><p>Al visitar la web como administrador se revisa el horario cada doce horas. Si falla, se permite otro intento quince minutos después.</p><p>Horario: ${e(dateText(m?.last_schedule_success))} · Fichas completadas: ${e(dateText(m?.last_success))} · ${m?.remaining || 0} listados pendientes · ${m?.catalog_jobs?.pending||0} trabajos de catálogo · ${m?.catalog_jobs?.failed||0} trabajos de catálogo fallidos · ${m?.quarantined || 0} fichas requieren revisión.</p>${m?.error ? `<p class="form-error">${e(m.error)} · ${e(dateText(m.error_at))}</p>` : '<p class="muted">Sin errores recientes del scraper.</p>'}<div class="toolbar">${button('site_maintenance', 'Revisar si corresponde', 'refresh', '', 'ghost')}${m?.catalog_jobs?.failed?button('data_retry','Reintentar catálogo','refresh','','ghost'):''}${m?.quarantined ? button('maintenance_retry_failed','Reintentar fichas con errores','refresh','','ghost') : ''}${button('cron_config', m?.external_enabled ? 'Configurar actualización externa' : 'Acerca de la actualización externa', 'calendar', '', 'ghost')}</div></section>`
    : '';
}
document.addEventListener('click', async (event) => {
  const b = event.target.closest(
    '[data-play],[data-mal-edit],[data-mal-match],[data-mal-filter],[data-action]'
  );
  if (!b) return;
  const action = b.dataset.action,
    handled = [
      'mal_list',
      'mal_refresh_all',
      'mal_xml_open',
      'mal_xml_commit',
      'mal_page_prev',
      'mal_page_next',
      'mal_choose',
      'mal_find',
      'mal_unlink',
      'mal_remove_prompt',
      'mal_remove_confirm',
      'player_extension',
      'notifications_read',
      'site_maintenance',
      'maintenance_retry_failed',
      'cron_config',
      'browser_notifications',
      'pwa_install',
    ];
  if (
    !b.dataset.play &&
    !b.dataset.malEdit &&
    !b.dataset.malMatch &&
    !b.dataset.malFilter &&
    !handled.includes(action)
  )
    return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (b.disabled) return;
  const interaction = dialogTicket();
  b.disabled = true;
  try {
    if (b.dataset.play) {
      await openPlayer(Number(b.dataset.play));
      return;
    }
    if (b.dataset.malEdit) {
      if (requireUser()) await editMal(Number(b.dataset.malEdit));
      return;
    }
    if (b.dataset.malMatch) {
      if (requireUser()) await matchMal(Number(b.dataset.malMatch));
      return;
    }
    if (b.dataset.malFilter) {
      malFilters.status = b.dataset.malFilter;
      malFilters.page = 1;
      malLibraryPage = null;
      navigate('mal');
      return;
    }
    if (action === 'pwa_install') {
      await installWebApp();
      return;
    }
    if (action === 'browser_notifications') {
      if (!('Notification' in window))
        throw new Error('Este navegador no admite avisos.');
      const permission = await Notification.requestPermission();
      localStorage.setItem(
        'seasonav1.notice',
        permission === 'granted' ? 'yes' : 'no'
      );
      toast(
        permission === 'granted'
          ? 'Avisos activados mientras esta web esté abierta.'
          : 'Puedes seguir usando la campana de avisos.'
      );
      return;
    }
    if (!requireUser()) return;
    if (action === 'mal_list') {
      navigate('mal');
      return;
    }
    if (action === 'mal_refresh_all') {
      await refreshMal();
      return;
    }
    if (action === 'mal_xml_open') {
      document.querySelector('#mal-xml-file').click();
      return;
    }
    if (action === 'mal_xml_commit') {
      const r = await api('mal_xml', { xml: xmlPreview, commit: true });
      xmlPreview = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      malLibraryPage = null;
      await loadMalLibrary();
      render();
      toast(r.message);
      return;
    }
    if (action === 'mal_page_prev' || action === 'mal_page_next') {
      malFilters.page = Math.max(
        1,
        Math.min(
          malLibraryPage.pages,
          malLibraryPage.page + (action === 'mal_page_next' ? 1 : -1)
        )
      );
      await loadMalLibrary();
      return;
    }
    if (action === 'mal_choose') {
      const r = await api('mal_link', {
        mal_id: Number(b.dataset.id),
        slug: b.dataset.slug,
      });
      malLibraryPage = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      if (view === 'mal') await loadMalLibrary();
      render();
      toast(r.message);
      return;
    }
    if (action === 'mal_find') {
      showMalFind(b.dataset.slug);
      return;
    }
    if (action === 'mal_unlink') {
      const r = await api('mal_unlink', { mal_id: Number(b.dataset.id) });
      malLibraryPage = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      if (view === 'mal') await loadMalLibrary();
      render();
      toast(r.message);
      return;
    }
    if (action === 'mal_remove_prompt') {
      modal(
        `<p class="eyebrow">RETIRAR DE MYANIMELIST</p><h2>¿Retirar este anime de tu lista de MAL?</h2><p>Se eliminará su estado, puntuación y progreso en tu cuenta de MAL.</p><div class="toolbar">${button('mal_remove_confirm', 'Retirar de MAL', 'close', `data-id="${b.dataset.id}" data-account="${Number(b.dataset.account) || 0}"`, 'danger')}${button('close', 'Conservar', '', '', 'ghost')}</div>`
      );
      return;
    }
    if (action === 'mal_remove_confirm') {
      const r = await api('mal_remove', {
        mal_id: Number(b.dataset.id),
        confirmation: 'QUITAR',
        mal_account_id: Number(b.dataset.account),
      });
      malLibraryPage = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      if (view === 'mal') await loadMalLibrary();
      render();
      toast(r.message);
      return;
    }
    if (action === 'player_extension') {
      playerExtensionHelp();
      return;
    }
    if (action === 'notifications_read') {
      await api(action, {
        up_to: noticesUpTo,
      });
      noticesPage = null;
      render();
      return;
    }
    if (action === 'maintenance_retry_failed') {
      const r = await api(action);
      renderFeaturePage();
      toast(r.message);
      maintainSite().catch(error => toast(error.message,true));
      return;
    }
    if (action === 'site_maintenance') {
      const r = await api('maintenance');
      toast(
        r.maintenance_result.skipped
          ? r.maintenance_result.reason
          : r.maintenance_result.failed_slug ? 'La ficha falló; los demás animes continuarán.' : r.maintenance_result.updated_slug ? 'Ficha actualizada.' : 'Horario actualizado.'
      );
      render();
      return;
    }
    if (action === 'cron_config') {
      if (!featureHome?.maintenance?.external_enabled) {
        modal(
          '<p class="eyebrow">ACTUALIZACIÓN DEL SITIO</p><h2>Se actualiza cuando visitas la web.</h2><p>InfinityFree gratuito bloquea los cron externos, incluidos cron-job.org y los monitores usados como cron. La revisión se activa al visitar como administrador, como máximo cada doce horas, y continúa los listados pendientes con pausas.</p><p>El endpoint protegido queda disponible para un alojamiento que permita tareas programadas; está desactivado aquí.</p>'
        );
        return;
      }
      modal(
        `<p class="eyebrow">ACTUALIZACIÓN EXTERNA</p><h2>Un endpoint protegido.</h2><p>En un alojamiento compatible, configura un POST cada cinco minutos desde tu servicio de automatización. El servidor revisa el horario cada doce horas y procesa un listado de capítulos por solicitud.</p><form id="cron-token-form">${securityField('cron', 'current_password', 'Contraseña actual')}<p class="form-error"></p><button class="button primary" type="submit">Generar token de actualización</button></form><small>Generar otro token invalida el anterior. Se muestra una sola vez.</small>`
      );
      return;
    }
  } catch (error) {
    toast(error.message, true);
  } finally {
    b.disabled = false;
  }
});
document.addEventListener('submit', async (event) => {
  const f = event.target;
  if (
    ![
      'mal-edit-form',
      'mal-match-search',
      'mal-find-form',
      'cron-token-form',
    ].includes(f.id)
  )
    return;
  event.preventDefault();
  event.stopImmediatePropagation();
  const b = f.querySelector('[type="submit"]');
  b.disabled = true;
  const user = state.user?.id, interaction = dialogTicket();
  try {
    let r;
    if (f.id === 'mal-edit-form') {
      const correction={};
      if(Number(f.elements.watched.value)<Number(f.dataset.watched)||f.elements.correct_progress?.checked){
        if(!await experienceConfirm('¿Corregir el progreso hacia abajo en MAL y en la web? Se cancelarán los envíos pendientes.'))return;
        correction.confirmation='CORREGIR';correction.reconcile_local=true;
      }
      r = await api('mal_save', {
        ...correction,
        mal_id: Number(f.dataset.id),
        mal_account_id: Number(f.dataset.account),
        status: f.elements.status.value,
        watched: Number(f.elements.watched.value),
        score: Number(f.elements.score.value),
      });
      if (state.user?.id !== user) return;
      document.dispatchEvent(new CustomEvent('season-form-saved',{detail:f}));
      malLibraryPage = null;
      statsPage = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      if (view === 'mal') await loadMalLibrary();
      render();
      toast(r.message);
    }
    if (f.id === 'mal-match-search')
      await matchMal(Number(f.dataset.id), f.elements.search.value);
    if (f.id === 'mal-find-form') {
      r = await api('mal_search', { query: f.elements.query.value });
      if (!f.isConnected || state.user?.id !== user) return;
      $('#mal-find-results').innerHTML =
        r.matches
          .map(
            (m) =>
              `<article class="match-row"><div><strong>${e(m.title)}</strong><span>${e(m.media_type)} · ${e(m.start_date || 'Fecha sin datos')}</span></div><button class="button primary" data-action="mal_choose" data-id="${m.mal_id}" data-slug="${e(f.dataset.slug)}">Vincular esta ficha</button></article>`
          )
          .join('') || '<p>No hay resultados. Prueba otro título.</p>';
    }
    if (f.id === 'cron-token-form') {
      r = await api('maintenance_token', {
        current_password: f.elements.current_password.value,
      });
      if (state.user?.id !== user || !dialogCurrent(interaction,true)) return;
      modal(
        `<p class="eyebrow">GUARDA ESTE TOKEN</p><h2>POST cada cinco minutos.</h2><p>URL: <code>${e(r.endpoint)}</code></p><p>Encabezado de autorización:</p><pre class="secret-display">Authorization: Bearer ${e(r.maintenance_token)}</pre><p>No publiques ni compartas este token. El horario también se revisa al visitar la web como administrador.</p>`
      );
    }
  } catch (error) {
    const node = f.querySelector('.form-error');
    if (node && f.isConnected) node.textContent = error.message;
    else toast(error.message, true);
  } finally {
    b.disabled = false;
  }
});
document.addEventListener('change', async (event) => {
  const t = event.target;
  try {
    if (t.id === 'mal-status') {
      malFilters.status = t.value;
      malFilters.page = 1;
      await loadMalLibrary();
    }
    if (t.id === 'player-server' && playerView) {
      rememberPlayerServer(playerView,Number(t.value));
      playerView.index = Number(t.value);
      renderPlayer();
    }
    if (t.id === 'player-chapter') await openPlayer(Number(t.value));
    if (t.id === 'appearance-theme' || t.id === 'appearance-accent')
      setAppearance(t.id === 'appearance-theme' ? 'theme' : 'accent', t.value);
    if (t.id === 'mal-xml-file') {
      const file = t.files[0];
      if (!file) return;
      if (file.size > 10 * 1024 * 1024)
        throw new Error('El XML puede ocupar hasta 10 MB.');
      xmlPreview = await file.text();
      const r = await api('mal_xml', { xml: xmlPreview, commit: false });
      modal(
        `<p class="eyebrow">IMPORTAR XML DE MAL</p><h2>${r.preview.count} animes para tu colección.</h2><p>Se combinarán estados, puntuaciones, notas y progreso con tu lista guardada en esta web. No se escribirá en MAL.</p><ul>${r.preview.sample.map((m) => `<li>${e(m.title)} · ${e(MAL_STATUSES[m.status])} · ${m.watched} vistos</li>`).join('')}</ul><div class="toolbar">${button('mal_xml_commit', 'Importar a esta web', 'upload', '', 'primary')}${button('close', 'Cancelar', '', '', 'ghost')}</div>`
      );
      t.value = '';
    }
  } catch (error) {
    toast(error.message, true);
  }
});
let malSearchTimer;
document.addEventListener('input', (event) => {
  if (event.target.id === 'mal-search') {
    malFilters.search = event.target.value;
    malFilters.page = 1;
    clearTimeout(malSearchTimer);
    malSearchTimer = setTimeout(
      () => loadMalLibrary().catch((err) => toast(err.message, true)),
      400
    );
  }
});
function startFeaturePolling() {
  clearInterval(featureTimer);
  featureUser = Number(state?.user?.id || 0);
  featureTimer = setInterval(() => {
    if (document.hidden || !state?.user) return;
    if (featureUser !== state.user.id) {
      featureUser = state.user.id;
      resetFeatures();
    }
    loadFeatureHome(false).catch(() => {});
    updateFeatureHeader();
  }, 120000);
}
setInterval(() => {
  if (!document.hidden) updateFeatureHeader();
}, 60000);
document.addEventListener('visibilitychange', () => {
  scheduleWatchPump();
  if (
    !document.hidden &&
    state?.user?.is_admin &&
    (featureHome?.maintenance?.remaining || featureHome?.maintenance?.catalog_due)
  )
    maintainSite().catch((error) => toast(error.message, true));
});
document.querySelector('#dialog').addEventListener('close', () => {
  if (document.querySelector('#dialog-body .episode-player')) {
    playerController?.destroy();
    playerController = null;
    document.querySelector('#dialog-body').replaceChildren();
    playerView = null;
  }
  xmlPreview = null;
  if (state?.user?.is_admin && (featureHome?.maintenance?.remaining || featureHome?.maintenance?.catalog_due))
    maintainSite().catch((error) => toast(error.message, true));
});
