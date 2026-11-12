'use strict';
let liveJobs = new Map(),
  lastBridgeCheck = 0,
  settingsApplied = '',
  settingsSyncBusy = false,
  settingsSyncPromise = null,
  bridgeMessage = '',
  settingsGeneration = 0;
const LIVE_LABELS = {
  queued: 'En cola',
  downloading: 'Descargando',
  verifying: 'Verificando',
  paused: 'Pausado',
  failed: 'Falló',
  confirmed: 'Descargado',
  cancelled: 'Retirado'
};
function connectionLabel() {
  return bridge.connected
    ? 'App conectada'
    : bridge.token
      ? 'No detectada'
      : 'Sin emparejar';
}
function connectionDescription() {
  return bridge.connected
    ? 'Preparar capítulos los envía directamente. El estado y los capítulos terminados se actualizan aquí mientras la página esté visible.'
    : bridge.token
      ? 'Abre YomaTV para enviar la cola y recibir su estado. Mientras tanto puedes usar las opciones de respaldo.'
      : 'Empareja YomaTV una vez para enviar capítulos y recibir su estado automáticamente. Los archivos JSON siguen disponibles como respaldo.';
}
function connectionMarkup() {
  return `<span class="connection-dot ${bridge.connected ? 'online' : bridge.token ? 'offline' : 'unpaired'}"></span><span>${connectionLabel()}</span>`;
}
function webPreferences() {
  return {
    ...state.settings,
    favorites: state.anime
      .filter((a) => a.favorite)
      .map((a) => a.slug)
      .sort(),
    exclusions: state.anime
      .filter((a) => a.excluded)
      .map((a) => a.slug)
      .sort()
  };
}
function settingsKey() {
  return `seasonav1.settings-sync.${state.installation}.${state.user.id}`;
}
function invalidateSettingsSync() {
  settingsGeneration++;
  settingsApplied = '';
  bridgeMessage = '';
  lastBridgeCheck = 0;
  if (state?.user) try { localStorage.removeItem(settingsKey()); } catch (_) {}
}
function settingsStamp() {
  return JSON.stringify(webPreferences());
}
function applySettingsNow(force = false) {
  if (!state?.user || !state.preferences_saved || !bridge.token)
    return Promise.resolve({ applied: false });
  if (settingsSyncBusy)
    return force
      ? settingsSyncPromise.then(() => applySettingsNow(true))
      : settingsSyncPromise;
  const stamp = settingsStamp(),
    user = state.user.id,
    generation = settingsGeneration, token = bridge.token,
    key = settingsKey();
  if (!force) {
    try {
      if ((settingsApplied || localStorage.getItem(key)) === stamp)
        return Promise.resolve({ applied: true });
    } catch (_) {}
  }
  settingsSyncBusy = true;
  settingsSyncPromise = (async () => {
    try {
      if (!bridge.connected || !bridge.capabilities.length) await bridge.ping();
      if (state.user?.id !== user || generation !== settingsGeneration || token !== bridge.token) return { applied: false };
      if (!bridge.supports('settings')) {
        bridgeMessage =
          'Actualiza YomaTV para aplicar preferencias al instante.';
        return { applied: false, legacy: true };
      }
      await bridge.settings(webPreferences());
      if (state.user?.id !== user || generation !== settingsGeneration || token !== bridge.token) return { applied: false };
      settingsApplied = stamp;
      try {
        localStorage.setItem(key, stamp);
      } catch (_) {}
      bridgeMessage = 'Preferencias aplicadas en la PC.';
      return { applied: true };
    } catch (error) {
      bridgeMessage =
        'Guardadas en la web. Se aplicarán cuando la app vuelva a conectar.';
      return { applied: false, message: error.message };
    } finally {
      settingsSyncBusy = false;
      updateBridgeUI();
    }
  })();
  return settingsSyncPromise;
}
function jobView(job) {
  if (job.status === 'confirmed')
    return {
      phase: 'confirmed',
      label: LIVE_LABELS.confirmed,
      glyph: 'check',
      progress: 100
    };
  if (job.status === 'cancelled')
    return {
      phase: 'cancelled',
      label: LIVE_LABELS.cancelled,
      glyph: 'close',
      progress: 0
    };
  const live = bridge.connected ? liveJobs.get(Number(job.id)) : null;
  if (live) {
    const phase =
      live.status === 'completed'
        ? 'verifying'
        : live.status === 'pending'
          ? 'queued'
          : live.status;
    return {
      phase,
      label:
        live.status === 'completed'
          ? 'Confirmando…'
          : live.reason || LIVE_LABELS[phase] || 'En cola',
      glyph:
        phase === 'failed'
          ? 'close'
          : phase === 'paused'
            ? 'pause'
            : phase === 'queued'
              ? 'check'
              : 'download',
      progress: Number(live.progress) || 0
    };
  }
  if(job.last_pc_state&&['failed','paused'].includes(job.last_pc_state.state)){const s=job.last_pc_state;return {phase:s.state,label:'Último estado: '+(s.state==='failed'?'falló':'pausado'),glyph:s.state==='failed'?'close':'pause',progress:0};}
  return {
    phase: 'queued',
    label:
      job.status === 'pending'
        ? 'En cola web'
        : bridge.connected
          ? 'Enviado a la PC'
          : 'Pendiente de la app',
    glyph: 'check',
    progress: 0
  };
}
function jobStatus(job) {
  const s = jobView(job);
  return `<span class="status-pill ${s.phase}" title="${e(s.label)}">${icon(s.glyph)}${e(s.label)}${s.phase === 'downloading' ? ` · ${Math.floor(s.progress)}%` : ''}</span>${['downloading', 'verifying'].includes(s.phase) ? `<span class="job-progress" role="progressbar" aria-label="Progreso del capítulo ${e(job.number)}" aria-valuenow="${Math.round(s.progress)}" aria-valuemin="0" aria-valuemax="100"><i style="width:${s.progress}%"></i></span>` : ''}`;
}
function sendableJobs() {
  return activeJobs().filter((j) => {
    const live = bridge.connected ? liveJobs.get(Number(j.id)) : null;
    return !live || ['failed', 'paused'].includes(live.status);
  });
}
function latestJob(anime) {
  return (
    state.jobs.find(
      (j) =>
        j.slug === anime.slug &&
        String(j.number) === String(anime.latest) &&
        j.language === state.settings.language &&
        j.status !== 'cancelled'
    ) || anime.latest_job
  );
}
function cardDownload(anime) {
  const job = latestJob(anime),
    s = job && job.status !== 'cancelled' ? jobView(job) : null;
  if (!s && !anime.latest && !state.user?.is_admin) {
    return `<button class="button small ghost" data-open="${e(anime.slug)}" aria-label="Ver capítulos de ${e(anime.title)}" title="Ver capítulos de ${e(anime.title)}">${icon('library')}Capítulos</button>`;
  }
  if (!s)
    return button(
      'queue_one',
      'Preparar',
      'download',
      `data-slug="${e(anime.slug)}" aria-label="Preparar el último capítulo de ${e(anime.title)}" title="Preparar el último capítulo de ${e(anime.title)}"`,
      'small ghost'
    );
  if (s.phase === 'failed')
    return button(
      'queue_one',
      'Reintentar',
      'refresh',
      `data-slug="${e(anime.slug)}" aria-label="Reintentar descarga de ${e(anime.title)}" title="Reintentar descarga de ${e(anime.title)}"`,
      'small ghost failed'
    );
  const text =
    s.phase === 'confirmed'
      ? 'Descargado'
      : s.phase === 'downloading'
        ? `${Math.floor(s.progress)}%`
        : s.phase === 'verifying'
          ? 'Verificando'
          : s.phase === 'paused'
            ? 'Pausado'
            : 'En cola';
  return `<button class="button small ghost ${s.phase}" ${s.phase === 'confirmed' ? `data-open="${e(anime.slug)}"` : 'data-view="queue"'} aria-label="${e(s.label)} · ${e(anime.title)}" title="${e(s.label)} · ${e(anime.title)}">${icon(s.glyph)}${e(text)}</button>`;
}
function updateBridgeUI() {
  const pill = document.querySelector('#bridge-indicator');
  if (pill) {
    pill.innerHTML = connectionMarkup();
    pill.setAttribute('aria-label', `YomaTV: ${connectionLabel()}`);
    pill.title = bridge.connected
      ? 'YomaTV está disponible en este equipo.'
      : bridge.token
        ? 'Abre YomaTV en este equipo.'
        : 'Empareja tu PC para comprobar la conexión.';
  }
  document
    .querySelectorAll('[data-connection-label]')
    .forEach((el) => (el.textContent = connectionLabel()));
  document
    .querySelectorAll('[data-connection-description]')
    .forEach((el) => (el.textContent = connectionDescription()));
  document
    .querySelectorAll('[data-connection-dot]')
    .forEach(
      (el) =>
        (el.className = `connection-dot ${bridge.connected ? 'online' : bridge.token ? 'offline' : 'unpaired'}`)
    );
  const message = document.querySelector('#settings-sync-status');
  if (message)
    message.textContent =
      bridgeMessage ||
      (bridge.connected
        ? 'Guardar aplica los cambios en YomaTV.'
        : 'Los cambios se sincronizan cuando la app conecta.');
  document.querySelectorAll('[data-job-status]').forEach((el) => {
    const j = state?.jobs.find((j) => j.id == el.dataset.jobStatus);
    if (j) {
      const html = jobStatus(j);
      if (el.innerHTML !== html) el.innerHTML = html;
    }
  });
  document.querySelectorAll('[data-job-row]').forEach((el) => {
    const j = state.jobs.find((j) => j.id == el.dataset.jobRow);
    if (j)
      el.hidden = queueFilter !== 'all' && jobView(j).phase !== queueFilter;
  });
  document.querySelectorAll('[data-action="cancel_job"]').forEach((el) => {
    const j = state.jobs.find((j) => j.id == el.dataset.id);
    if (j) el.hidden = !['pending', 'exported'].includes(j.status);
  });
  document
    .querySelectorAll('[data-action="export"]')
    .forEach((el) => (el.disabled = !sendableJobs().length));
  document.querySelectorAll('[data-card-download]').forEach((el) => {
    const a = lookupAnime(el.dataset.cardDownload);
    if (a) {
      const html = cardDownload(a);
      if (el.innerHTML !== html) {
        const focused = el.contains(document.activeElement);
        el.innerHTML = html;
        if (focused) el.querySelector('button')?.focus({ preventScroll: true });
      }
    }
  });
  if (state) {
    const total = document.querySelector('#queue-badge');
    if (total) total.textContent = activeJobs().length;
    document.querySelectorAll('[data-queue-count]').forEach((el) => {
      const phase = el.dataset.queueCount;
      el.textContent = state.jobs.filter((j) =>
        phase === 'queued'
          ? jobView(j).phase === 'queued'
          : phase === 'downloading'
            ? ['downloading', 'verifying'].includes(jobView(j).phase)
            : jobView(j).phase === phase
      ).length + (phase === 'confirmed' && state.queue_totals ? Math.max(0,state.queue_totals.confirmed-state.jobs.filter(j=>j.status==='confirmed').length) : 0);
    });
  }
  if (typeof updateDownloadUI === 'function') updateDownloadUI();
}
function scheduleResults(delay) {
  clearTimeout(resultsTimer);
  if (!resultsBusy && !document.hidden && bridge.token)
    resultsTimer = setTimeout(
      syncResults,
      delay ?? (state?.user && activeJobs().length ? 3000 : 15000)
    );
}
async function queryBridgeBatches(method, jobs, user) {
  const values = [];
  for (let offset = 0; offset < jobs.length; offset += 2000) {
    if (state.user?.id !== user) return null;
    const result = await bridge[method](
      state.installation,
      jobs.slice(offset, offset + 2000).map((job) => Number(job.id))
    );
    if (state.user?.id !== user) return null;
    values.push(result);
  }
  return values;
}
async function syncResults() {
  if (resultsBusy || document.hidden || !bridge.token) return;
  resultsBusy = true;
  try {
    const wasConnected = bridge.connected;
    if (!bridge.connected || Date.now() - lastBridgeCheck > 30000) {
      await bridge.ping();
      lastBridgeCheck = Date.now();
    }
    if (state?.user) {
      const changedUser = resultUser !== state.user.id;
      if (changedUser) {
        resultUser = state.user.id;
        resultSignature = '';
        liveJobs.clear();
        settingsApplied = '';
      }
      const user = resultUser;
      if(bridge.connected)await ensureQueueHistory('',{all:true,active:true});
      if(state.user?.id!==user)return;
      const jobs = activeJobs();
      if (jobs.length) {
        let needsReceipts = !bridge.supports('live_status');
        if (bridge.supports('live_status')) {
          const batches = await queryBridgeBatches('status', jobs, user);
          if (!batches) return;
          const statuses = batches.flatMap((batch) => batch.jobs);
          liveJobs = new Map(statuses.map((j) => [Number(j.web_id), j]));
          persistDownloadEvents(statuses,user).catch(()=>{});
          needsReceipts = statuses.some((j) => j.status === 'completed');
        }
        if (needsReceipts) {
          const batches = await queryBridgeBatches('results', jobs, user);
          if (!batches) return;
          const signature = JSON.stringify(
            batches.map((batch) => batch.signature)
          );
          if (signature !== resultSignature) {
            for (const receipt of batches.flatMap((batch) => batch.receipts)) {
              if (state.user?.id !== user) return;
              await api('receipt', { receipt });
            }
            resultSignature = signature;
          }
        }
      }
      await applySettingsNow(!wasConnected || changedUser);
    }
  } catch (_) {
    bridge.connected = false;
    liveJobs.clear();
  } finally {
    resultsBusy = false;
    updateBridgeUI();
    scheduleResults();
  }
}
document.addEventListener('pointerup', (event) => {
  if (event.pointerType === 'mouse')
    event.target.closest('.nav-item,.day-tab')?.blur();
});
