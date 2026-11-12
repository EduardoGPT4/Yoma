'use strict';
let queueAnime = location.hash.startsWith('#queue/')
    ? location.hash.slice(7)
    : '',
  queuePage = 1;
const QUEUE_PAGE_SIZE = 36;
const queueHistoryLoads = new Map();

const queuePages=new Map();
function invalidateQueuePages(patch,full=false){
  const user=state?.user?.id;if(!user)return;const slugs=new Set([...(patch?.jobs||[]).map(j=>j.slug),...(patch?.queue_summary||[]).map(g=>g.slug)]);
  for(const key of queuePages.keys())if(key.startsWith(`${user}:`)&&(full||slugs.has(key.split(':')[1])))queuePages.delete(key);
}

async function ensureQueueHistory(slug,{all=false,active=false}={}) {
  if(!state?.user)return;
  const user=state.user.id,key=`${user}:${slug}:${active}`,old=queueHistoryLoads.get(key);
  if(old?.promise)return old.promise;
  const stamp=active?JSON.stringify((state.queue_summary||[]).map(g=>[g.slug,g.queued,g.last_id])):'';
  if(old?.complete&&old.stamp===stamp)return;
  const loading=old?.stamp===stamp?old:{before:0,complete:false,stamp};queueHistoryLoads.set(key,loading);
  loading.promise=(async()=>{
    do{const r=await api('queue_history',{slug,before:loading.before,active:active?'1':''},true);
      if(state.user?.id!==user)return;loading.before=Number(r.queue_history.next_before);loading.complete=!loading.before;
    }while(all&&!loading.complete);
  })().finally(()=>{loading.promise=null;});return loading.promise;
}
async function loadQueuePage(slug,page=1,phase=queueFilter,force=false){
  const user=state.user?.id;if(!user)return;const key=`${user}:${slug}:${phase}:${page}`;
  if(queuePages.has(key)&&!force)return;const entry={busy:true};queuePages.set(key,entry);
  try{const r=await api('queue_page',{slug,page,phase},true);if(state.user?.id!==user)return;Object.assign(entry,r.queue_page,{busy:false});if(view==='queue'&&queueAnime===slug&&queueFilter===phase&&queuePage===page){queuePage=entry.page;queuePages.set(`${user}:${slug}:${phase}:${entry.page}`,entry);}}
  catch(error){entry.busy=false;entry.error=error.message;}
  if(state.user?.id===user&&view==='queue'&&queueAnime===slug)render();
}

function groupedJobs() {
  const groups = new Map((state.queue_summary || []).map(summary => [summary.slug, { ...summary, summary, jobs: [] }]));
  for (const job of state.jobs) {
    if (!groups.has(job.slug))
      groups.set(job.slug, {
        slug: job.slug,
        title: job.title,
        cover: job.cover,
        jobs: [],
      });
    groups.get(job.slug).jobs.push(job);
  }
  for (const group of groups.values())
    group.jobs.sort(
      (a, b) =>
        Number(a.number) - Number(b.number) ||
        a.language.localeCompare(b.language)
    );
  return [...groups.values()];
}
function groupState(group) {
  const statuses = group.jobs.map(jobView),
    counts = group.summary ? { queued: group.queued, confirmed: group.confirmed, cancelled: group.cancelled, failed:group.failed||0 } : {};
  statuses.forEach((status, index) => {
    if (group.summary) {
      const stored = group.jobs[index].status;
      const base = ['pending','exported'].includes(stored) ? 'queued' : stored;
      counts[base] = (counts[base] || 0) - 1;
    }
    counts[status.phase] = (counts[status.phase] || 0) + 1;
  });
  const phase =
    ['downloading', 'verifying', 'failed', 'paused', 'queued'].find(
      (p) => counts[p]
    ) || (counts.confirmed ? 'confirmed' : 'cancelled');
  return {
    phase,
    counts,
    total: group.summary ? group.total : statuses.length,
    progress:
      (statuses.reduce((sum, status) => sum + status.progress, 0) +
        (group.summary ? Math.max(0,group.confirmed-group.jobs.filter(j=>j.status==='confirmed').length)*100 : 0)) /
      Math.max(1,group.summary ? group.total : statuses.length),
  };
}
function groupStatus(group) {
  const s = groupState(group),
    current = ['downloading', 'verifying'].includes(s.phase)
      ? group.jobs.find((j) => jobView(j).phase === s.phase)
      : null;
  const label = current
    ? `${LIVE_LABELS[s.phase]} · EP ${current.number}`
    : s.counts.confirmed === s.total
      ? 'Selección descargada'
      : LIVE_LABELS[s.phase];
  return `<span class="status-pill ${s.phase}">${icon(s.phase === 'confirmed' ? 'check' : s.phase === 'paused' ? 'pause' : s.phase === 'failed' ? 'close' : 'download')}${e(label)}</span>${['downloading', 'verifying'].includes(s.phase) ? `<span class="job-progress"><i style="width:${s.progress}%"></i></span>` : ''}`;
}
function groupCount(group) {
  const s = groupState(group);
  return `${s.counts.confirmed || 0} / ${s.total} descargados`;
}
function groupMatches(group) {
  return (
    (queueFilter === 'all' ||
      groupState(group).counts[queueFilter] > 0) &&
    group.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())
  );
}
function downloadStats() {
  return `<section class="stats"><div class="stat"><span class="stat-icon">${icon('download')}</span><div><strong data-queue-count="queued">0</strong><span>Capítulos en cola</span></div></div><div class="stat"><span class="stat-icon">${icon('pc')}</span><div><strong data-queue-count="downloading">0</strong><span>Descargando / verificando</span></div></div><div class="stat"><span class="stat-icon">${icon('check')}</span><div><strong data-queue-count="confirmed">0</strong><span>Capítulos descargados</span></div></div></section>`;
}
function queueFilterSelect() {
  return `<select id="queue-filter" class="select-input compact" aria-label="Estado de las descargas"><option value="all">Todos los estados</option>${Object.entries(
    LIVE_LABELS
  )
    .map(
      ([key, label]) =>
        `<option value="${key}" ${queueFilter === key ? 'selected' : ''}>${label}</option>`
    )
    .join('')}</select>`;
}
function queueBackups() {
  return `<details class="queue-backup"><summary>${icon('download')}Opciones de respaldo</summary><p>Si no puedes conectar con la app, guarda tu cola para importarla en YomaTV. También puedes importar sus resultados verificados.</p><div class="toolbar">${button('download_json', 'Guardar cola JSON', 'download', '', 'ghost')}${button('receipt', 'Importar resultados', 'upload', '', 'ghost')}</div></details>`;
}
function downloadQueueView() {
  if (!state.user)
    return (
      title(
        'WEB + YOMATV',
        'Tus descargas, por anime.',
        'Abre un anime para consultar sus capítulos.'
      ) +
      empty(
        'Tus descargas, organizadas',
        'Inicia sesión y conecta YomaTV para preparar capítulos.',
        button('account', 'Iniciar sesión', 'pc', '', 'primary'),
        'download'
      )
    );
  const groups = groupedJobs();
  if (queueAnime) {
    if (state.queue_summary) queueMicrotask(() => loadQueuePage(queueAnime,queuePage));
    return queueAnimeView(groups.find((group) => group.slug === queueAnime));
  }
  return (
    title(
      'WEB + YOMATV',
      'Tus descargas, por anime.',
      'Cada anime ocupa una fila. Ábrelo para ver sus capítulos y su progreso.',
      button('export', 'Enviar a la PC', 'pc', '', 'primary')
    ) +
    connectionPanel() +
    downloadStats() +
    `<div class="filter-bar">${queueFilterSelect()}${searchBox()}<span class="responsive-count">${groups.length} ${groups.length === 1 ? 'anime' : 'animes'} · ${state.queue_totals?.total ?? state.jobs.length} capítulos</span></div>${groups.length ? `<div class="jobs-list queue-anime-list"><div class="queue-anime-header"><span>ANIME</span><span>CAPÍTULOS</span><span>ESTADO EN LA PC</span><span></span></div>${groups.map((group) => `<button data-ui-key="queue-${e(group.slug)}" class="queue-anime-row" data-queue-open="${e(group.slug)}" aria-label="Ver capítulos de ${e(group.title)}" ${groupMatches(group) ? '' : 'hidden'}><span class="job-anime"><img src="${e(group.cover)}" alt="" loading="lazy"><span><strong>${e(group.title)}</strong><small>${e((group.languages || [...new Set(group.jobs.map((j) => j.language))]).join(' · '))} · ${group.total ?? group.jobs.length} capítulos</small></span></span><span class="queue-group-count" data-group-count="${e(group.slug)}">${groupCount(group)}</span><span class="job-live" data-group-status="${e(group.slug)}">${groupStatus(group)}</span><span class="queue-chevron" aria-hidden="true">›</span></button>`).join('')}</div><p class="queue-no-matches" ${groups.some(groupMatches) ? 'hidden' : ''}>Ningún anime coincide con esta búsqueda o estado.</p>` : empty('Tu próxima descarga empieza aquí', 'Prepara un anime desde el catálogo o el horario.', button('view_discover', 'Explorar catálogo', 'compass', '', 'primary'), 'download')}` +
    queueBackups()
  );
}
function queueAnimeView(group) {
  if (!group)
    return (
      button('queue_back', 'Volver a mis animes', 'arrow', '', 'ghost') +
      empty(
        'Este anime no está en tus descargas',
        'Puedes prepararlo desde su ficha.'
      )
    );
  return `<div class="queue-detail-navigation">${button('queue_back', 'Volver a mis animes', 'arrow', '', 'ghost')}${button('queue_detail', 'Ver ficha y preparar capítulos', 'plus', `data-slug="${e(group.slug)}"`, 'ghost')}</div><section class="queue-anime-hero"><img src="${e(group.cover)}" alt="Portada de ${e(group.title)}"><div><p class="eyebrow">TUS DESCARGAS</p><h1>${e(group.title)}</h1><p data-group-count="${e(group.slug)}">${groupCount(group)}</p><div class="job-live" data-group-status="${e(group.slug)}">${groupStatus(group)}</div></div></section>${queueGroupControls(group)}<div class="filter-bar">${queueFilterSelect()}<span class="muted">Capítulos en orden numérico · los descargados están bloqueados</span></div><div id="queue-chapters" aria-live="polite">${queueChapters(group)}</div><div class="queue-detail-actions">${button('queue_send', 'Enviar pendientes de este anime', 'pc', `data-slug="${e(group.slug)}"`, 'primary')}</div><p class="queue-footnote">Los estados corresponden al idioma indicado. Retirar una solicitud web no cancela una descarga que la PC ya inició.</p>`;
}
function queueChapters(group) {
  const entry=queuePages.get(`${state.user?.id}:${group.slug}:${queueFilter}:${queuePage}`);
  if(!entry||entry.busy)return '<p class="muted" role="status">Cargando capítulos…</p>';
  if(entry.error)return `<p class="form-error">${e(entry.error)}</p><button class="button ghost" data-action="queue_history_retry" data-slug="${e(group.slug)}">Reintentar</button>`;
  const labels={connection:'Sin conexión',server:'Servidor no disponible',disk:'Error de disco',verification:'Falló la integridad',unknown:'Error de descarga'};
  return `<div class="queue-chapter-count">${entry.total} capítulos · Página ${entry.page} de ${entry.pages}</div><div class="queue-chapter-grid">${entry.items.map(job=>{
    const event=entry.events.find(ev=>Number(ev.job_id)===Number(job.id)),failure=event?.state==='failed'&&job.status!=='confirmed';
    return `<article class="queue-chapter" data-queue-chapter="${job.id}"><div class="queue-chapter-heading"><strong>EP ${e(job.number)}</strong><span>${e(job.language)}</span></div><small>${e(job.server)} · ${job.height}p preferido</small><div data-job-status="${job.id}">${jobStatus(job)}</div>${failure?`<p class="form-error">${e(labels[event.error_kind]||labels.unknown)} · ${Number(event.attempts)>0?Number(event.attempts)+' intentos':'Intentos no informados por esta app'}</p>`:''}${event?`<small>Último estado informado por la PC: ${e(dateText(Number(event.updated_at)))}</small>`:''}<div class="file-presence-wrapper">${filePresenceMarkup(job)}</div>${['pending','exported'].includes(job.status)?`<button class="text-button queue-remove" data-action="cancel_job" data-id="${job.id}">Retirar de la web</button>`:''}</article>`;
  }).join('')}</div>${entry.items.length?'':'<p>No hay capítulos con este estado.</p>'}<nav class="queue-pagination" aria-label="Páginas de capítulos">${button('queue_previous','Anterior','',entry.page===1?'disabled':'','ghost')}<span>${entry.page} / ${entry.pages}</span>${button('queue_next','Siguiente','',entry.page===entry.pages?'disabled':'','ghost')}</nav>`;
}

function episodeDownload(ep) {
  const known = state.jobs.find(
    (j) =>
      Number(j.episode_id) === Number(ep.id) &&
      j.language === state.settings.language
  );
  const job =
    known ||
    (ep.download_job_id
      ? { id: Number(ep.download_job_id), status: ep.download_status }
      : null);
  return job
    ? jobView(job)
    : { phase: 'available', label: 'Disponible', progress: 0 };
}
function episodeCanPrepare(ep) {
  return !['confirmed', 'queued', 'downloading', 'verifying'].includes(
    episodeDownload(ep).phase
  );
}
function episodeTiles(eps) {
  return eps
    .map((ep) => {
      const rewatch=typeof detailState!=='undefined'&&detailState?.watch_mode?.mode==='rewatch',seen=rewatch?ep.rewatched:ep.watched;
      const status = episodeDownload(ep),
        done = status.phase === 'confirmed',
        allowed = episodeCanPrepare(ep);
      return `<div class="episode ${seen ? 'seen' : ''} ${done ? 'downloaded' : ''}" data-download-episode="${ep.id}"><strong>EP ${e(ep.number)}</strong><span class="episode-download-status ${status.phase}">${done ? icon('check') : ''}${e(status.label)}</span><label><input class="episode-select" type="checkbox" value="${ep.id}" aria-label="Seleccionar capítulo ${e(ep.number)}" ${allowed ? '' : 'disabled'} ${typeof episodeSelection==='function'&&episodeSelection().has(Number(ep.id))&&allowed?'checked':''}>${done ? 'Descargado' : allowed ? 'Elegir' : 'Ya preparado'}</label><button class="episode-watch-button" data-play="${ep.id}">▶ Ver capítulo</button><button data-action="watched" data-id="${ep.id}" data-watched="${!seen}">${seen ? (rewatch?'✓ Revisado':'✓ Visto') : (rewatch?'Marcar revisado':'Marcar visto')}</button>${state.user?.is_admin || Number(ep.mirrors_at) > Date.now() / 1000 - 1800 ? `<button data-action="mirrors" data-id="${ep.id}">Servidores ↗</button>` : ''}</div>`;
    })
    .join('');
}
function updateDownloadUI() {
  if (!state) return;
  if(typeof updateGroupControls==='function')updateGroupControls();
  const groups = groupedJobs(),
    bySlug = new Map(groups.map((group) => [group.slug, group]));
  document.querySelectorAll('[data-queue-open]').forEach((el) => {
    const group = bySlug.get(el.dataset.queueOpen);
    if (group) el.hidden = !groupMatches(group);
  });
  document.querySelectorAll('[data-group-count]').forEach((el) => {
    const group = bySlug.get(el.dataset.groupCount);
    if (group) el.textContent = groupCount(group);
  });
  document.querySelectorAll('[data-group-status]').forEach((el) => {
    const group = bySlug.get(el.dataset.groupStatus);
    if (group) {
      const html = groupStatus(group);
      if (el.innerHTML !== html) el.innerHTML = html;
    }
  });
  const noMatches = document.querySelector('.queue-no-matches');
  if (noMatches) noMatches.hidden = groups.some(groupMatches);
  document
    .querySelectorAll('[data-action="queue_send"]')
    .forEach(
      (el) =>
        (el.disabled = !sendableJobs().some((j) => j.slug === el.dataset.slug))
    );
  if (detailState && document.querySelector('#dialog')?.open) {
    if(typeof updateDetailProgressDownloads==='function')updateDetailProgressDownloads(detailState.episodes);
    for (const ep of detailState.episodes) {
      const tile = document.querySelector(
        `[data-download-episode="${Number(ep.id)}"]`
      );
      if (!tile) continue;
      const rewatch=typeof detailState!=='undefined'&&detailState?.watch_mode?.mode==='rewatch',seen=rewatch?ep.rewatched:ep.watched;
      const status = episodeDownload(ep),
        done = status.phase === 'confirmed',
        input = tile.querySelector('.episode-select'),
        badge = tile.querySelector('.episode-download-status');
      tile.classList.toggle('downloaded', done);
      badge.className = `episode-download-status ${status.phase}`;
      badge.innerHTML = `${done ? icon('check') : ''}${e(status.label)}`;
      input.disabled = !episodeCanPrepare(ep);
      if (input.disabled) input.checked = false;
      input.parentElement.lastChild.textContent = done
        ? 'Descargado'
        : input.disabled
          ? 'Ya preparado'
          : 'Elegir';
    }
    const available = detailState.episodes.some(episodeCanPrepare),
      all = document.querySelector('[data-action="queue_all"]');
    if (all) all.disabled = !detailState.anime.catalog_complete || !available;
    const selected = document.querySelector('[data-action="queue_selected"]');
    if (selected)
      selected.disabled = typeof episodeSelectionIds==='function'?episodeSelectionIds().length===0:!document.querySelector('.episode-select:checked:not(:disabled)');
    const count=document.querySelector('[data-selection-count]');if(count&&typeof episodeSelectionIds==='function')count.textContent=`${episodeSelectionIds().length} seleccionados`;
  }
}
function openQueueAnime(slug) {
  if (queueAnime && queueAnime !== slug) queueHistoryLoads.delete(`${state.user?.id}:${queueAnime}`);
  const recent = state.jobs.filter(job=>!['pending','exported'].includes(job.status)).slice(0,80);
  const keep = new Set(recent.map(job=>Number(job.id)));
  state.jobs = state.jobs.filter(job=>['pending','exported'].includes(job.status) || job.slug===slug || keep.has(Number(job.id)));
  queueAnime = slug;
  queuePage = 1;
  queueFilter = 'all';
  view = 'queue';
  location.hash = 'queue/' + slug;
  render();
  document.querySelector('#main').scrollTo({ top: 0 });
  window.scrollTo({ top: 0 });
}
document.addEventListener('click', async (event) => {
  const row = event.target.closest('[data-queue-open]');
  if (row) {
    event.preventDefault();
    openQueueAnime(row.dataset.queueOpen);
    return;
  }
  const b = event.target.closest('[data-action^="queue_"]');
  if (!b) return;
  const action = b.dataset.action;
  if (
    ![
      'queue_back',
      'queue_detail',
      'queue_previous',
      'queue_next',
      'queue_send',
      'queue_history_retry',
    ].includes(action)
  )
    return;
  event.stopImmediatePropagation();
  if (b.disabled) return;
  if (action === 'queue_history_retry') {
    await loadQueuePage(b.dataset.slug,queuePage,queueFilter,true);
    return;
  }
  if (action === 'queue_back') {
    queueAnime = '';
    queuePage = 1;
    queueFilter = 'all';
    navigate('queue');
  }
  if (action === 'queue_detail') showDetail(b.dataset.slug);
  if (action === 'queue_previous' || action === 'queue_next') {
    queuePage += action === 'queue_next' ? 1 : -1;
    render();
    document
      .querySelector('#queue-chapters')
      ?.scrollIntoView({ block: 'start' });
  }
  if (action === 'queue_send') {
    b.disabled = true;
    try {
      await ensureQueueHistory(b.dataset.slug,{all:true,active:true});
      const ids = sendableJobs()
        .filter((j) => j.slug === b.dataset.slug)
        .map((j) => Number(j.id));
      if (ids.length) await sendToPC(ids);
    } catch (error) {
      toast(error.message, true);
    } finally {
      updateDownloadUI();
    }
  }
});
document.addEventListener('change', (event) => {
  if (event.target.id === 'queue-filter') queuePage = 1;
  if (event.target.classList.contains('episode-select')) updateDownloadUI();
});
window.addEventListener('hashchange', () => {
  const hash = location.hash.slice(1);
  if (hash.startsWith('queue/') && queueAnime !== hash.slice(6)) {
    queueAnime = hash.slice(6);
    queuePage = 1;
    view = 'queue';
    render();
  } else if (hash === 'queue' && queueAnime) {
    queueAnime = '';
    queuePage = 1;
    view = 'queue';
    render();
  }
});
