'use strict';
const $ = (s) => document.querySelector(s);
const e = (v) =>
  String(v ?? '').replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ]
  );
const icon = (n) => `<svg aria-hidden="true"><use href="#i-${n}"/></svg>`;
const DAYS = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const TITLES = {
  discover: 'Catálogo completo',
  schedule: 'Temporada',
  radio: 'Radio anime',
  library: 'Mi biblioteca',
  favorites: 'Favoritos',
  queue: 'Cola para la PC',
  history: 'Actividad',
  settings: 'Preferencias',
  account: 'Mi cuenta',
  mal: 'Mi lista MAL',
  stats: 'Estadísticas',
  notifications: 'Capítulos nuevos',
};
const FOLLOW = {
  watching: 'Viendo',
  planned: 'Por ver',
  completed: 'Completado',
  paused: 'En pausa',
  dropped: 'Dejado',
};
const JOBS = {
  pending: 'Preparado',
  exported: 'Enviado a la PC',
  confirmed: 'Confirmado',
  cancelled: 'Retirado',
};
let state = null,
  view = TITLES[location.hash.slice(1).split(/[/?]/)[0]]
    ? location.hash.slice(1).split(/[/?]/)[0]
    : 'discover',
  day = 0,
  search = '',
  libraryFilter = 'all',
  queueFilter = 'all',
  detailState = null,
  toastTimer,
  authMode = 'login';
const bridge = new SeasonBridge(
  Number($('meta[name="bridge-port"]')?.content || 47653)
);
const radio = new AnimeRadio();
let detailSequence = 0;
const detailDrafts = new Map();
function dialogTicket() {
  return { sequence: detailSequence, user: state?.user?.id || 0, view };
}
function dialogCurrent(ticket, open = false) {
  return ticket.sequence === detailSequence && ticket.user === (state?.user?.id || 0) && ticket.view === view && (!open || $('#dialog').open);
}
function captureDetailDraft() {
  const form = document.querySelector('#detail-form');
  if (!form || !state?.user || Number(form.dataset.user) !== state.user.id) return;
  const values = Object.fromEntries(new FormData(form));
  values.excluded = form.elements.excluded.checked;
  detailDrafts.set(`${state.user.id}:${form.dataset.slug}`, values);
}
function restoreDetailDraft(slug) {
  const values = detailDrafts.get(`${state.user?.id}:${slug}`), form = document.querySelector('#detail-form');
  if (!values || !form || form.dataset.slug !== slug) return;
  form.dataset.originalDraftBaseline=JSON.stringify({...Object.fromEntries(new FormData(form)),excluded:form.elements.excluded.checked});
  for (const [key,value] of Object.entries(values)) {
    const field = form.elements.namedItem(key);
    if (field) field.type === 'checkbox' ? field.checked = Boolean(value) : field.value = value;
  }
}
let resultsTimer,
  resultsBusy = false,
  resultSignature = '',
  resultUser = null;
function toast(text, error = false) {
  clearTimeout(toastTimer);
  const t = $('#toast');
  t.textContent = text;
  t.className = 'toast show' + (error ? ' error' : '');
  toastTimer = setTimeout(() => (t.className = 'toast'), 4500);
}
let dialogReturnFocus=null;
function modal(html) {
  captureDetailDraft();
  detailSequence++;
  radio.pause('En pausa mientras la ficha está abierta.');
  $('#dialog-body').innerHTML = html;
  if (!$('#dialog').open) {dialogReturnFocus=document.activeElement;$('#dialog').showModal();}
}
function requireUser() {
  if (state?.user) return true;
  showAuth();
  return false;
}
function exeDownload(style = 'ghost', label = 'Descargar .exe') {
  const url = $('meta[name="desktop-download-url"]')?.getAttribute('content');
  return url
    ? `<a class="button ${style}" href="${e(url)}" target="_blank" rel="noopener noreferrer" title="AnimeAV1 Plus para Windows · Google Drive">${icon('download')}${e(label)}</a>`
    : '';
}
function connectionPanel() {
  return `<div class="note-banner"><span data-connection-dot class="connection-dot ${bridge.connected ? 'online' : bridge.token ? 'offline' : 'unpaired'}"></span><div><strong data-connection-label>${connectionLabel()}</strong><p data-connection-description>${connectionDescription()}</p></div>${button('connect', bridge.token ? 'Ver conexión' : 'Conectar PC', 'pc', '', 'ghost')}</div>`;
}
function connectPC() {
  modal(
    `<div class="auth-form"><p class="eyebrow">WEB + SEASONAV1</p><h2>Un clic aquí.<br>La descarga en tu PC.</h2><p>¿Todavía no tienes la aplicación?</p><div class="toolbar">${exeDownload('small ghost', 'Descargar AnimeAV1 Plus.exe')}</div><p>Abre AnimeAV1 Plus, pulsa <b>Conectar web</b> y copia el código. La aplicación debe permanecer en la bandeja de este mismo equipo.</p><form id="bridge-form"><div class="field"><label for="bridge-code">Código de tu equipo</label><input id="bridge-code" name="code" class="form-input" type="password" autocomplete="off" spellcheck="false" minlength="43" maxlength="43" required></div><p>Tu navegador puede pedir acceso a la red local. Permítelo para conectar con AnimeAV1 Plus. El código se guarda solo en este navegador y no se envía al alojamiento.</p><details class="brave-help"><summary>Uso Brave y no conecta</summary><p>Junto a la dirección de esta página abre los controles del sitio → Configuración del sitio. Busca <b>Acceso a la red local</b> (o <b>Localhost</b> en versiones anteriores) y permite el acceso para <b>https://tv.yoma.site</b>. Vuelve a cargar la página y empareja de nuevo. Si Brave ofrece una duración, elige la que prefieras.</p><a href="https://support.brave.app/hc/en-us/articles/360018205431-How-do-I-change-site-permissions" target="_blank" rel="noopener noreferrer">Ayuda oficial de Brave ↗</a></details><p id="bridge-error" class="form-error"></p><button type="submit" class="button primary wide">${icon('pc')}Emparejar y comprobar</button></form>${bridge.token ? `<div class="toolbar" style="margin-top:16px">${button('disconnect', 'Olvidar este equipo', 'close', '', 'ghost')}</div>` : ''}<p>Si el navegador no permite la conexión, el archivo JSON sigue funcionando.</p></div>`
  );
}
function title(eyebrow, heading, text, actions = '') {
  return `<div class="page-title"><div><p class="eyebrow">${e(eyebrow)}</p><h1>${e(heading)}</h1><p>${e(text)}</p></div>${actions}</div>`;
}
function empty(heading, text, button = '', glyph = 'library') {
  return `<div class="empty">${icon(glyph)}<h3>${e(heading)}</h3><p>${e(text)}</p>${button}</div>`;
}
function searchBox() {
  return `<label class="search-box">${icon('search')}<input id="search" type="search" placeholder="Buscar un anime…" aria-label="Buscar anime" value="${e(search)}"></label>`;
}
function dateText(value) {
  if (!value) return 'Sin actualización';
  const d =
    typeof value === 'number' ? new Date(value * 1000) : new Date(value);
  return new Intl.DateTimeFormat('es-MX', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Mexico_City',
  }).format(d);
}
function button(action, text, glyph = '', extra = '', style = '') {
  return `<button class="button ${style}" data-action="${action}" ${extra}>${glyph ? icon(glyph) : ''}${e(text)}</button>`;
}
function card(a, progress = false) {
  return `<article class="anime-card"><a class="poster" href="#anime-${e(a.slug)}" data-open="${e(a.slug)}" aria-label="Ver ${e(a.title)}"><img src="${e(a.cover)}" alt="Portada de ${e(a.title)}" loading="lazy" decoding="async"><span class="episode-badge">${a.latest ? `EP ${e(a.latest)}` : e(a.category)}</span>${a.active ? `<span class="card-status">${e(DAYS[a.weekday - 1])}</span>` : '<span class="card-status">Catálogo</span>'}</a><button class="card-favorite ${a.favorite ? 'selected' : ''}" data-action="favorite" data-slug="${e(a.slug)}" aria-label="${a.favorite ? 'Quitar' : 'Añadir'} favorito" aria-pressed="${a.favorite}">${icon('star')}</button><a href="#anime-${e(a.slug)}" data-open="${e(a.slug)}"><h3 class="card-title">${e(a.title)}</h3></a><div class="card-meta"><span>${e(a.category)}</span><span class="dot"></span><span>${a.catalog_complete ? `${a.episodes} cap. disponibles` : 'Ver capítulos'}</span></div>${a.next_airing ? `<p class="airing-countdown" data-countdown="${a.next_airing}"></p>` : ''}${a.mal ? `<p class="mal-card-progress">MAL · ${e(MAL_STATUSES[a.mal.status] || 'Sin estado')} · ${a.mal.watched} vistos</p>` : ''}${progress ? `<div class="watch-progress"><span style="width:${Math.min(100, (a.watched / Math.max(1, a.episodes)) * 100)}%"></span></div><div class="watch-caption">${a.watched} de ${a.episodes} vistos · ${e(FOLLOW[a.status] || 'Por ver')}</div>` : ''}<div class="card-actions">${a.status !== 'none' ? `<button class="text-button card-follow following" data-open="${e(a.slug)}" aria-label="En tu biblioteca · Abrir ${e(a.title)}" title="En tu biblioteca · Abrir ficha">${icon('check')}</button>` : `<button class="text-button card-follow" data-action="follow" data-slug="${e(a.slug)}" aria-label="Seguir ${e(a.title)}" title="Seguir anime">${icon('plus')}</button>`}<span class="card-download" data-card-download="${e(a.slug)}">${cardDownload(a)}</span></div></article>`;
}
function cards(rows, progress = false) {
  return rows.length
    ? `<div class="card-grid">${rows.map((a) => card(a, progress)).join('')}</div>`
    : empty('Sin animes aquí todavía', 'Prueba otro día o cambia tu búsqueda.');
}
function discover() {
  return catalogView();
}
function schedule() {
  const rows = state.anime.filter(
    (a) =>
      a.active &&
      (!day || a.weekday === day) &&
      a.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())
  );
  return (
    title(
      'DEL LUNES AL DOMINGO',
      'Cada estreno tiene su día.',
      'El horario se agrupa por la última publicación en hora de Ciudad de México.',
      state.user?.is_admin
        ? button('sync', 'Actualizar horario', 'refresh')
        : ''
    ) +
    `<div class="filter-bar"><div class="day-tabs" role="group" aria-label="Filtrar día">${[0, 1, 2, 3, 4, 5, 6, 7].map((d) => `<button class="day-tab ${day === d ? 'active' : ''}" data-day="${d}" aria-pressed="${day === d}">${d ? ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][d - 1] : 'Todos'}</button>`).join('')}</div>${searchBox()}</div><div class="section-heading"><p>${rows.length} ${rows.length === 1 ? 'anime' : 'animes'} · Actualizado ${e(dateText(state.updated_at))}</p><div class="toolbar"><a class="button small ghost" href="calendar.php">Exportar calendario (.ics)</a>${button('calendar_open','Mi calendario','calendar','','small ghost')}${button('queue_day', 'Preparar últimos', 'download', `data-day="${day}"`, 'small ghost')}</div></div>${cards(rows)}`
  );
}
function queue() {
  return downloadQueueView();
}
function activity() {
  return (
    title(
      'LO QUE PASÓ EN TU TEMPORADA',
      'Pequeños pasos, buenas historias.',
      'Tu registro de colas, confirmaciones y cambios de preferencias.'
    ) +
    (state.history.length
      ? `<div class="history-list">${state.history.map((h) => `<article class="history-item"><strong>${e(h.message)}</strong><span>${e(dateText(Number(h.created_at)))}</span></article>`).join('')}</div>`
      : empty(
          'Tu actividad aparecerá aquí',
          'Cada cola exportada y descarga confirmada deja un registro en tu cuenta.',
          button(
            state.user ? 'view_schedule' : 'account',
            state.user ? 'Explorar horario' : 'Iniciar sesión',
            'compass',
            '',
            'primary'
          ),
          'history'
        ))
  );
}
function select(name, label, options, help = '') {
  return `<div class="field"><label for="setting-${name}">${e(label)}</label><select class="select-input" name="${name}" id="setting-${name}">${Object.entries(
    options
  )
    .map(
      ([v, l]) =>
        `<option value="${v}" ${String(state.settings[name]) === v ? 'selected' : ''}>${e(l)}</option>`
    )
    .join('')}</select>${help ? `<small>${e(help)}</small>` : ''}</div>`;
}
function input(name, label, type, help = '', attrs = '') {
  return `<div class="field"><label for="setting-${name}">${e(label)}</label><input class="form-input" id="setting-${name}" name="${name}" type="${type}" value="${e(state.settings[name])}" ${attrs}>${help ? `<small>${e(help)}</small>` : ''}</div>`;
}
function settings() {
  const intro = title(
    'A TU MANERA',
    'Configura tus descargas.',
    'Guardar sincroniza las preferencias con la app conectada. Si está cerrada, las recibe al volver a conectar.'
  );
  if (!state.user)
    return (
      intro +
      empty(
        'Guarda tus preferencias',
        'Inicia sesión para elegir idioma, servidor y cómo organizar tus descargas.',
        button('account', 'Iniciar sesión', 'settings', '', 'primary'),
        'settings'
      )
    );
  return (
    intro +
    `<form id="settings-form"><div class="settings-grid"><section class="panel"><h2 class="panel-title">${icon('download')}Descarga e idioma</h2><div class="field-pair">${select('language', 'Idioma', { SUB: 'SUB · Subtitulado', LAT: 'LAT · Español latino', DUB: 'DUB · Doblado' })}${select('height', 'Calidad preferida', { 1080: '1080p', 720: '720p' })}</div>${select('quality_fallback', 'Si falta esa calidad', { best: 'Mejor disponible', lower: 'Resolución menor', wait: 'Esperar calidad exacta' })}${select('language_fallback', 'Si falta el idioma', { wait: 'Esperar el idioma elegido', SUB: 'Usar SUB' })}${select('server', 'Servidor preferido', { MP4Upload: 'MP4Upload', Voe: 'Voe' })}${select('server_fallback', 'Si falla el servidor', { wait: 'Esperar ese servidor', other: 'Probar el otro compatible' })}</section><section class="panel"><h2 class="panel-title">${icon('settings')}Horario y velocidad</h2>${input('review_time', 'Hora de revisión', 'time', 'Hora local de Windows. Se sincroniza con su tarea programada.', 'required')}${input('workers', 'Animes a la vez (1–4)', 'number', 'Cada anime descarga sus capítulos en orden. La primera revisión completa usa una sola descarga.', 'min="1" max="4" required')}${input('speed_kib', 'Límite total (KiB/s)', 'number', '0 significa sin límite.', 'min="0" max="1000000" required')}<p class="settings-hint">Puedes cambiar el ritmo sin borrar archivos: AnimeAV1 Plus conserva los parciales.</p></section><section class="panel"><h2 class="panel-title">${icon('library')}Tu biblioteca</h2>${select('selection', 'Revisiones automáticas', { all: 'Todo el horario', favorites: 'Solo favoritos' })}${select('season_source', 'Carpeta inicial', { current: 'Temporada actual', premiere: 'Temporada de estreno' })}${select('long_series', 'Si cruza otra temporada', { keep: 'Mantener carpeta inicial', split: 'Separar por temporada' })}<div class="field"><label>Carpeta de destino</label><small>Se elige en AnimeAV1 Plus y se conserva al sincronizar con la web.</small></div><p class="settings-hint">Los favoritos y las exclusiones se sincronizan con estas preferencias. Excluir un anime evita sus próximas descargas.</p></section></div><div class="settings-footer"><div><strong data-connection-label>${connectionLabel()}</strong><p id="settings-sync-status">${e(bridgeMessage || 'Guardar aplica las preferencias en AnimeAV1 Plus.')}</p></div><button class="button primary" type="submit">${icon('check')}Guardar preferencias</button></div></form>`
  );
}
function render() {
  if (!state) return;
  radio.setLibraryScope?.(state.user?.id);
  $('#breadcrumb').textContent = TITLES[view];
  $('#season-label').textContent = state.season;
  $('#account').innerHTML =
    `<span class="avatar">${e((state.user?.name || 'S').slice(0, 1).toUpperCase())}</span><span>${e(state.user?.name || 'Mi cuenta')}</span>`;
  $('#queue-badge').textContent = activeJobs().length;
  document
    .querySelectorAll('[data-view]')
    .forEach((b) =>
      b.classList.toggle(
        'active',
        b.dataset.view === view && b.classList.contains('nav-item')
      )
    );
  const renderers = {
    discover,
    schedule,
    radio: radioView,
    library: () => library(false),
    favorites: () => library(true),
    queue,
    history: activity,
    settings,
    account: accountView,
    mal: typeof malLibraryView === 'function' ? malLibraryView : discover,
    stats: typeof statisticsView === 'function' ? statisticsView : activity,
    notifications:
      typeof notificationsView === 'function' ? notificationsView : activity,
  };
  $('#main').innerHTML = renderers[view]();
  if (view === 'settings' && typeof themeControls === 'function')
    $('#main').insertAdjacentHTML('beforeend', themeControls() + adminPanel());
  updateBridgeUI();
  if (typeof updateFeatureHeader === 'function') updateFeatureHeader();
  document.title = `${TITLES[view]} · SeasonAV1`;
  scheduleResults();
}
function navigate(name) {
  if (!TITLES[name]) return;
  if (name === 'queue') {
    queueAnime = '';
    queuePage = 1;
  }
  view = name;
  search = '';
  libraryFilter = 'all';
  if (name === 'discover' && !catalogState) loadCatalog();
  location.hash = name === 'discover' ? catalogRoute().slice(1) : name;
  render();
  sidebarNavigation.closeMobile();
  $('#main').scrollTo({ top: 0, behavior: 'auto' });
  window.scrollTo({ top: 0, behavior: 'smooth' });
}
function help() {
  modal(
    `<div class="help-heading"><img src="assets/icon-192.png?v=20261015-human-v3" alt="Icono de SeasonAV1"><div><p class="eyebrow">WEB + PC</p><h2>Organiza aquí.<br>Disfruta allá.</h2></div></div><div class="help-step"><span class="step-number">01</span><div><strong>Conecta tu equipo una vez</strong><p>En AnimeAV1 Plus pulsa <b>Conectar web</b>, copia su código y pégalo aquí. Permite el acceso a la red local cuando lo solicite el navegador.</p></div></div><div class="help-step"><span class="step-number">02</span><div><strong>Prepara y descarga</strong><p>Preparar, Preparar todos o Preparar seleccionados envía esos capítulos al programa y comienza la descarga en la bandeja. Si no está disponible, se descarga un JSON para usar Importar cola web.</p></div></div><div class="help-step"><span class="step-number">03</span><div><strong>Comprueba tu cola</strong><p>Mientras esta página esté abierta, confirma los capítulos terminados y verificados por la PC. Si no hay conexión directa, aún puedes Exportar resultados web e Importar resultados manualmente.</p></div></div><p>Funciona desde un navegador en el mismo equipo. Puedes cerrar la web: las descargas y las revisiones diarias continúan en AnimeAV1 Plus.</p><div class="toolbar">${exeDownload('ghost', 'Descargar AnimeAV1 Plus.exe')}${button('connect', 'Conectar con AnimeAV1 Plus', 'pc', '', 'primary')}${button('view_queue', 'Ir a mi cola', 'download', '', 'ghost')}</div>`
  );
}
async function showDetail(slug) {
  modal(
    '<div class="loading-view"><span class="spinner"></span><p>Cargando esta historia…</p></div>'
  );
  const sequence = detailSequence,
    user = state.user?.id ?? 0;
  try {
    let result = await api('detail', { slug }, true);
    if (
      sequence !== detailSequence ||
      !$('#dialog').open ||
      user !== (state.user?.id ?? 0)
    )
      return;
    if (state.user?.is_admin && !result.detail.anime.catalog_complete) {
      try {
        result = await api('sync_anime', { slug }, false, {
          assignDetail: false,
        });
      } catch (error) {
        result.detail.warning = error.message;
      }
      if (
        sequence !== detailSequence ||
        !$('#dialog').open ||
        user !== (state.user?.id ?? 0)
      )
        return;
    }
    detailState = result.detail;
    renderDetail();
  } catch (err) {
    if (sequence === detailSequence && $('#dialog').open)
      modal(
        empty(
          'No se pudo abrir el anime',
          err.message,
          button('close', 'Cerrar', '', '', 'ghost')
        )
      );
  }
}
function renderDetail() {
  if (!detailState) return;
  const personal = lookupAnime(detailState.anime.slug);
  const a = { ...detailState.anime };
  for (const k of ['status', 'favorite', 'excluded', 'score', 'notes'])
    if (personal) a[k] = personal[k];
  const eps = detailState.episodes;
  modal(
    `<div class="detail-hero"><img class="detail-cover" src="${e(a.cover)}" alt="Portada de ${e(a.title)}"><div class="detail-info"><p class="eyebrow">${a.active ? e(DAYS[a.weekday - 1]) + ' · ' : ''}${e(a.category)}</p><h2>${e(a.title)}</h2><div class="detail-tags">${a.season ? `<span>${e(a.season)}</span>` : ''}${a.latest ? `<span>Último: ${e(a.latest)}</span>` : `<span>${a.catalog_complete ? 'Sin capítulos publicados' : 'Listado pendiente'}</span>`}${a.favorite ? '<span>★ Favorito</span>' : ''}</div>${typeof catalogMetadataInfo === 'function' ? catalogMetadataInfo(a) : ''}<p>${e(a.synopsis || 'Una nueva historia para tu temporada.')}</p><div class="toolbar">${button('favorite', a.favorite ? 'Favorito' : 'Guardar favorito', 'star', `data-slug="${e(a.slug)}"`, 'small lavender')}${button('queue_all', 'Preparar todos', 'download', `data-slug="${e(a.slug)}" ${!a.catalog_complete || !eps.some(episodeCanPrepare) ? 'disabled' : ''}`, 'small primary')}</div></div></div>${
      state.user
        ? `<form id="detail-form" data-user="${state.user.id}" data-slug="${e(a.slug)}" class="detail-form"><select class="select-input" name="status" aria-label="Estado en tu biblioteca">${Object.entries(
            FOLLOW
          )
            .map(
              ([k, v]) =>
                `<option value="${k}" ${a.status === k ? 'selected' : ''}>${v}</option>`
            )
            .join(
              ''
            )}</select><select class="select-input" name="score" aria-label="Puntuación"><option value="0">Sin nota</option>${Array.from(
            { length: 10 },
            (_, i) => i + 1
          )
            .map(
              (n) =>
                `<option value="${n}" ${a.score === n ? 'selected' : ''}>${n}/10</option>`
            )
            .join(
              ''
            )}</select><textarea class="form-input" name="notes" placeholder="Una nota para tu yo de la próxima temporada…" maxlength="2000" aria-label="Notas personales">${e(a.notes)}</textarea><div class="toolbar"><button class="button small ghost" type="submit">${icon('check')}Guardar en biblioteca</button><label class="muted" style="font-size:10px"><input type="checkbox" name="excluded" ${a.excluded ? 'checked' : ''}> Excluir de las descargas</label></div></form>`
        : ''
    }${state.user && typeof sourceMalPanel === 'function' ? sourceMalPanel(a) : ''}${typeof detailDataView==='function'?detailDataView(detailState):''}${typeof detailRelationsView==='function'?detailRelationsView(detailState):''}${state.user && !a.catalog_complete?`<button class="button small ghost" data-action="data_request" data-slug="${e(a.slug)}">Solicitar listado completo</button>`:''}<div class="episodes-header"><h3>Capítulos <span class="muted">(${eps.length})</span></h3>${state.user?.is_admin ? button('sync_anime', 'Actualizar listado', 'refresh', `data-slug="${e(a.slug)}"`, 'small ghost') : ''}</div>${detailState.warning ? `<p class="form-error">${e(detailState.warning)}</p>` : ''}${!a.catalog_complete && state.user?.is_admin ? '<p>Actualiza el listado antes de preparar todos los capítulos.</p>' : ''}${a.catalog_complete && !eps.length ? '<p>Este anime todavía no tiene capítulos publicados en AnimeAV1.</p>' : ''}${detailEpisodesView(eps)}<div class="toolbar" style="margin-top:20px">${button('queue_selected', 'Preparar seleccionados', 'download', `data-slug="${e(a.slug)}" disabled`, 'primary')}${a.status !== 'none' ? button('unfollow', 'Quitar de biblioteca', 'close', `data-slug="${e(a.slug)}"`, 'ghost') : ''}</div>`
  );
  restoreDetailDraft(a.slug);
  updateDownloadUI();
}
async function queueItems(slugs, mode = 'latest', ids = []) {
  if (!requireUser()) return;
  if(mode==='all'||mode==='selected'){ids=await previewQueue(slugs,mode,ids);if(!ids.length)return;mode='selected';}
  const r = await api('queue', { slugs, mode, episode_ids: ids });
  render();
  if (r.queue_ids.length) await sendToPC(r.queue_ids);
  else toast(r.message);
}
document.addEventListener('click', async (event) => {
  const b = event.target.closest(
    '[data-view],[data-action],[data-day],[data-open]'
  );
  if (!b) return;
  event.preventDefault();
  if (b.dataset.view) {
    $('#dialog').close();
    navigate(b.dataset.view);
    return;
  }
  if (b.dataset.open) {
    showDetail(b.dataset.open);
    return;
  }
  if (b.dataset.day !== undefined && !b.dataset.action) {
    day = Number(b.dataset.day);
    render();
    return;
  }
  const action = b.dataset.action,
    slug = b.dataset.slug;
  if (action?.startsWith('view_')) {
    $('#dialog').close();
    navigate(action.slice(5));
    return;
  }
  if (action === 'account') {
    if (state.user) openAccount();
    else showAuth();
    return;
  }
  if (action === 'auth_login') {
    showAuth('login');
    return;
  }
  if (action === 'auth_register') {
    showAuth('register');
    return;
  }
  if (action === 'help') {
    help();
    return;
  }
  if (action === 'close') {
    $('#dialog').close();
    return;
  }
  if (action === 'menu') {
    sidebarNavigation.toggle();
    return;
  }
  if (action === 'connect') {
    connectPC();
    return;
  }
  if (action === 'disconnect') {
    bridge.forget();
    invalidateSettingsSync();
    resultSignature = '';
    liveJobs.clear();
    settingsApplied = '';
    clearTimeout(resultsTimer);
    $('#dialog').close();
    render();
    toast('Este navegador olvidó la conexión con tu PC.');
    return;
  }
  if (action === 'retry') {
    init();
    return;
  }
  if (action?.startsWith('catalog_')) {
    b.disabled = true;
    try {
      await catalogAction(action, b);
    } catch (error) {
      toast(error.message, true);
    } finally {
      b.disabled = false;
    }
    return;
  }
  if (action === 'radio_start') {
    radio.play();
    return;
  }
  if (action === 'radio_stop') {
    radio.off();
    render();
    return;
  }
  if (action === 'radio_retry') {
    try {
      radio.setTracks((await api('radio', {}, true)).radio);
      render();
    } catch (error) {
      toast(error.message, true);
    }
    return;
  }
  if (action === 'receipt') {
    if (requireUser()) $('#receipt-file').click();
    return;
  }
  if (action === 'back_detail') {
    renderDetail();
    return;
  }
  if (
    [
      'favorite',
      'follow',
      'queue_one',
      'queue_day',
      'queue_all',
      'queue_selected',
      'watched',
      'sync',
      'sync_anime',
      'unfollow',
      'mirrors',
      'export',
      'download_json',
      'cancel_job',
    ].includes(action) &&
    !requireUser()
  )
    return;
  const interaction = dialogTicket();
  b.disabled = true;
  try {
    let r;
    if (action === 'logout') {
      r = await api('logout');
      $('#dialog').close();
      render();
      toast(r.message);
    } else if (action === 'favorite') {
      const a = lookupAnime(slug);
      const wasFavorite = a.favorite;
      r = await api('follow', { slug, favorite: !a.favorite });
      render();
      if (dialogCurrent(interaction, true) && detailState?.anime.slug === slug) renderDetail();
      toast(wasFavorite ? 'Favorito retirado.' : 'Añadido a tus favoritos.');
    } else if (action === 'follow') {
      await api('follow', { slug, status: 'watching' });
      render();
      toast('Añadido a tu biblioteca.');
    } else if (action === 'queue_one') {
      await queueItems([slug]);
    } else if (action === 'queue_day') {
      await queueItems(
        state.anime
          .filter(
            (a) =>
              a.active &&
              (!day || a.weekday === day) &&
              a.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())
          )
          .map((a) => a.slug)
      );
    } else if (action === 'queue_all') {
      const eps =
        detailState?.anime.slug === slug && $('#dialog').open
          ? detailState.episodes.filter(episodeCanPrepare)
          : null;
      if (eps) {
        if (!eps.length)
          throw new Error('Estos capítulos ya están descargados o preparados.');
        await queueItems(
          [slug],
          'selected',
          eps.map((ep) => Number(ep.id))
        );
      } else await queueItems([slug], 'all');
    } else if (action === 'queue_selected') {
      const ids = episodeSelectionIds();
      if (!ids.length) throw new Error('Selecciona al menos un capítulo.');
      await queueItems([slug], 'selected', ids);
    } else if (action === 'sync') {
      r = await api('sync');
      render();
      toast(r.message);
    } else if (action === 'sync_anime') {
      r = await api('sync_anime', { slug });
      render();
      if (dialogCurrent(interaction, true)) renderDetail();
      toast(r.message);
    } else if (action === 'watched') {
      await api('watched', {
        episode_id: Number(b.dataset.id),
        watched: b.dataset.watched === 'true',
        progress_revision:detailState?.watch_mode?.revision,
      });
      render();
      if (dialogCurrent(interaction, true)) renderDetail();
    } else if (action === 'unfollow') {
      r = await api('unfollow', { slug });
      render();
      if (dialogCurrent(interaction, true)) renderDetail();
      toast(r.message);
    } else if (action === 'cancel_job') {
      r = await api('cancel_job', { id: Number(b.dataset.id) });
      render();
      toast(r.message);
    } else if (action === 'export') {
      await sendToPC();
    } else if (action === 'download_json') {
      await sendToPC(undefined, true);
    } else if (action === 'mirrors') {
      r = await api('mirrors', { episode_id: Number(b.dataset.id) });
      if (!dialogCurrent(interaction,true)) return;
      const options = r.mirrors.sort(
        (a, b) =>
          Number(b.server === state.settings.server) -
          Number(a.server === state.settings.server)
      );
      modal(
        `<p class="eyebrow">CAPÍTULO ${e(r.episode.number)}</p><h2>Elige un servidor.</h2><p>Se abre el reproductor externo. Para una descarga verificada y reanudable, prepara el capítulo para AnimeAV1 Plus.</p><div class="toolbar">${options.map((m) => `<a class="button ${m.server === state.settings.server ? 'primary' : 'ghost'}" href="${e(m.url)}" target="_blank" rel="noopener noreferrer">${e(m.server)} · ${e(m.language)} ↗</a>`).join('') || '<p>No hay servidores compatibles disponibles en este capítulo.</p>'}</div><div style="margin-top:24px">${button('back_detail', 'Volver a capítulos', 'arrow', '', 'ghost')}</div>`
      );
    }
  } catch (err) {
    toast(err.message, true);
  } finally {
    b.disabled = false;
    updateDownloadUI();
  }
});
document.addEventListener('submit', async (event) => {
  if (event.target.id === 'bridge-form') {
    event.preventDefault();
    const form = event.target,
      submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    try {
      await bridge.pair(form.elements.code.value);
      invalidateSettingsSync();
      if (form.isConnected) $('#dialog').close();
      render();
      scheduleResults(1000);
      toast(
        'PC conectada. Preparar capítulos inicia su descarga en AnimeAV1 Plus.'
      );
    } catch (error) {
      if (form.isConnected)
        form.querySelector('.form-error').textContent = error.message;
    } finally {
      submit.disabled = false;
    }
    return;
  }
  const form = event.target;
  if (!['auth-form', 'settings-form', 'detail-form'].includes(form.id)) return;
  event.preventDefault();
  const submit = form.querySelector('[type="submit"]');
  const interaction = dialogTicket();
  submit.disabled = true;
  try {
    const input = Object.fromEntries(new FormData(form));
    let r;
    if (form.id === 'auth-form') {
      r = await api(form.dataset.mode, input);
      $('#dialog').close();
      render();
      toast(r.message);
    }
    if (form.id === 'settings-form') {
      r = await api('settings', input);
      document.dispatchEvent(new CustomEvent('season-form-saved',{detail:form}));
      const applied = await applySettingsNow(true);
      render();
      toast(
        applied.applied
          ? 'Preferencias guardadas y aplicadas en AnimeAV1 Plus.'
          : applied.legacy
            ? 'Guardadas en la web. Actualiza AnimeAV1 Plus para aplicarlas al instante.'
            : 'Guardadas en la web. Se aplicarán cuando AnimeAV1 Plus conecte.'
      );
      scheduleResults(1000);
    }
    if (form.id === 'detail-form') {
      input.slug = form.dataset.slug;
      input.excluded = form.elements.excluded.checked;
      input.score = Number(input.score);
      r = await api('follow', input);
      document.dispatchEvent(new CustomEvent('season-form-saved',{detail:form}));
      render();
      if (dialogCurrent(interaction, true)) renderDetail();
      toast(r.message);
    }
  } catch (err) {
    if (form.id === 'auth-form') $('#auth-error').textContent = err.message;
    else toast(err.message, true);
  } finally {
    submit.disabled = false;
  }
});
document.addEventListener('input', (event) => {
  if (event.target.id === 'search') {
    search = event.target.value;
    const position = event.target.selectionStart;
    render();
    $('#search').focus();
    $('#search').setSelectionRange(position, position);
  }
});
document.addEventListener('change', (event) => {
  if (event.target.id === 'library-filter') {
    libraryFilter = event.target.value;
    render();
  }
  if (event.target.id === 'queue-filter') {
    queueFilter = event.target.value;
    render();
  }
});
$('#receipt-file').addEventListener('change', async (event) => {
  const files = [...event.target.files];
  if (!files.length) return;
  try {
    let message = '';
    for (const file of files) {
      if (file.size > 2 * 1024 * 1024)
        throw new Error('Cada resultado puede ocupar hasta 2 MB.');
      const receipt = JSON.parse(await file.text()),
        r = await api('receipt', { receipt });
      message = r.message;
    }
    render();
    toast(
      files.length === 1
        ? message
        : `${files.length} archivos procesados. La cola muestra sus descargas confirmadas.`
    );
  } catch (err) {
    toast(err.message, true);
  } finally {
    event.target.value = '';
  }
});
document.addEventListener(
  'error',
  (event) => {
    if (event.target instanceof HTMLImageElement)
      event.target.parentElement.classList.add('image-failed');
  },
  true
);
$('#dialog').addEventListener('close', () => { captureDetailDraft(); detailSequence++; });
document.addEventListener('input', event => { if (event.target.closest('#detail-form')) captureDetailDraft(); });
document.addEventListener('change', event => { if (event.target.closest('#detail-form')) captureDetailDraft(); });
$('#dialog').addEventListener('click', (event) => {
  if (event.target === $('#dialog')) {
    const r = $('#dialog').getBoundingClientRect();
    if (
      event.clientX < r.left ||
      event.clientX > r.right ||
      event.clientY < r.top ||
      event.clientY > r.bottom
    )
      $('#dialog').close();
  }
});
window.addEventListener('hashchange', () => {
  sidebarNavigation.closeMobile();
  const animeRoute = /^#anime-([A-Za-z0-9_-]{1,240})$/.exec(location.hash);
  if (animeRoute && state) {
    showDetail(animeRoute[1]);
    return;
  }
  const next = location.hash.slice(1).split('?')[0];
  if (TITLES[next] && view !== next) {
    view = next;
    search = '';
    render();
  }
});
async function init() {
  try {
    await api('state', {}, true);
    render();
    if (typeof showMalCallbackNotice === 'function') showMalCallbackNotice();
    const animeRoute = /^#anime-([A-Za-z0-9_-]{1,240})$/.exec(location.hash);
    if (animeRoute) showDetail(animeRoute[1]);
    if (typeof loadFeatureHome === 'function')
      loadFeatureHome().catch((error) => toast(error.message, true));
    if (typeof startFeaturePolling === 'function') startFeaturePolling();
    await Promise.allSettled([
      loadCatalog(),
      api('radio', {}, true).then((r) => {
        radio.setTracks(r.radio);
        if (view === 'radio') render();
      }),
    ]);
  } catch (err) {
    $('#main').innerHTML = empty(
      'Tu temporada estará lista en un momento',
      err.message,
      button('retry', 'Volver a intentar', 'refresh', '', 'primary')
    );
  }
}
document.addEventListener('visibilitychange', () => scheduleResults(1000));
init();
