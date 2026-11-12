'use strict';
function radioView() {
  radio.setLibraryScope?.(state.user?.id);
  if (!radio.data)
    return (
      title(
        'YOMATV RADIO',
        'Dale música a tu próxima historia.',
        'La selección musical se está cargando.'
      ) +
      empty(
        'La radio aún no está disponible',
        'Puedes seguir explorando el catálogo y reintentar.',
        button('radio_retry', 'Reintentar', 'refresh', '', 'ghost'),
        'music'
      )
    );
  const data = radio.data,
    tracks = radio.playlist(),
    types = { OP: 'Opening', ED: 'Ending', OST: 'OST / soundtrack' };
  return `<section class="radio-hero"><div><p class="eyebrow">YOMATV RADIO · YOUTUBE</p><h1>Una temporada.<br><span>Muchas canciones.</span></h1><p>Openings, endings y bandas sonoras para acompañar<br>tu próxima historia.</p><div class="toolbar">${button('radio_start', radio.playing ? 'Pausar radio' : radio.minimized ? 'Ampliar y escuchar' : radio.enabled ? 'Reanudar radio' : 'Activar radio', radio.playing ? 'pause' : 'play', '', 'primary')}${radio.enabled ? button('radio_stop', 'Apagar radio', 'close', '', 'ghost') : ''}</div></div><div class="radio-record" aria-hidden="true"><div class="record-label">SA1<br><span>RADIO</span></div><i></i></div></section><div class="radio-settings panel"><div><strong>Música opcional, a tu ritmo.</strong><p id="radio-page-status">${e(radio.message)}</p></div><label class="radio-switch"><input id="radio-toggle" type="checkbox" ${radio.enabled ? 'checked' : ''}>Radio ${radio.enabled ? 'activada' : 'apagada'}</label></div><p class="radio-privacy">Al activar la radio se conecta con YouTube, que puede tratar tu dirección IP y usar cookies conforme a su <a href="https://policies.google.com/privacy" target="_blank" rel="noopener noreferrer">privacidad</a> y <a href="https://www.youtube.com/t/terms" target="_blank" rel="noopener noreferrer">condiciones</a>. Guardamos el volumen en este navegador; tus favoritos y listas se sincronizan con tu cuenta al iniciar sesión. Se pausa al minimizar la radio, ocultar la pestaña o abrir una ficha.</p><div class="section-heading"><div><h2>Lo que suena en ${e(data.season)}</h2><p>${data.tracks.filter((t) => t.type !== 'OST').length} temas de temporada · Selección revisada ${e(dateText(data.updated_at))}</p></div><a class="text-button" href="${e(data.ranking_source)}" target="_blank" rel="noopener noreferrer">Ver selección de origen ↗</a></div><p class="muted">${e(data.quality_note||'')}</p>${radioLibraryControls()}<div class="day-tabs radio-tabs" role="group" aria-label="Tipo de música">${Object.entries(
    { all: 'Todos', ...types }
  )
    .map(
      ([type, label]) =>
        `<button class="day-tab ${radio.type === type ? 'active' : ''}" data-radio-type="${type}" aria-pressed="${radio.type === type}">${label}</button>`
    )
    .join(
      ''
    )}</div><p class="radio-selection-note">${e(radio.type === 'OST' ? data.ost_note : data.ranking_note)}</p><div class="radio-list">${tracks.map(({ t }, i) => `<article data-ui-key="song-${t.id}" class="radio-song ${radio.enabled && radio.current.id === t.id ? 'selected' : ''}" data-radio-song="${t.id}"><span class="song-number">${String(i + 1).padStart(2, '0')}</span><button class="song-art" data-radio-start="${t.id}" aria-label="Reproducir ${e(t.title)}">${icon('play')}</button><div class="song-copy"><button data-radio-start="${t.id}" class="song-title">${e(t.title)}</button><span>${e(t.artist)} · ${e(t.anime)}</span><small>${e(t.channel)} · ${e(t.period)}</small></div>${radioSongLibrary(t)}<span class="song-type">${e(types[t.type])}</span><span class="song-views">${t.views === null ? '—' : new Intl.NumberFormat('es-MX', { notation: 'compact', maximumFractionDigits: 1 }).format(t.views)}<small>${t.views === null ? 'OST original' : 'vistas registradas'}</small></span><a class="icon-button" href="${e(t.url)}" target="_blank" rel="noopener noreferrer" aria-label="Abrir ${e(t.title)} en YouTube">↗</a></article>`).join('')}</div>`;
}
document.addEventListener('click', async (event) => {
  const b = event.target.closest(
    '[data-radio],[data-radio-start],[data-radio-type]'
  );
  if (!b) return;
  event.preventDefault();
  if (b.dataset.radioType) {
    radio.type = b.dataset.radioType;
    render();
    return;
  }
  if (b.dataset.radioStart) {
    radio.start(b.dataset.radioStart);
    return;
  }
  const action = b.dataset.radio;
  if (action === 'off') radio.off();
  if (action === 'play') radio.play();
  if (action === 'next') radio.next();
  if (action === 'previous') radio.next(-1);
  if (action === 'size') {
    if (radio.minimized) {
      radio.expand();
      radio.play();
    } else radio.minimize();
  }
});
document.addEventListener('change', (event) => {
  if (event.target.id === 'radio-toggle') {
    if (event.target.checked) radio.start();
    else radio.off();
  }
});
document.addEventListener('input', (event) => {
  if (event.target.id === 'radio-volume') radio.setVolume(event.target.value);
});
document.addEventListener('season-radio-change', () => {
  const playButton = document.querySelector('[data-action="radio_start"]');
  if (playButton) {
    playButton.lastChild.textContent = radio.playing
      ? 'Pausar radio'
      : radio.minimized
        ? 'Ampliar y escuchar'
        : radio.enabled
          ? 'Reanudar radio'
          : 'Activar radio';
    playButton
      .querySelector('use')
      ?.setAttribute('href', radio.playing ? '#i-pause' : '#i-play');
  }
  const dockPlay = document.querySelector('[data-radio="play"]');
  if (dockPlay) {
    const label = radio.playing
      ? 'Pausar'
      : radio.minimized
        ? 'Ampliar'
        : 'Reproducir';
    dockPlay.setAttribute('aria-label', label);
    dockPlay.querySelector('span').textContent = label;
    dockPlay
      .querySelector('use')
      .setAttribute('href', radio.playing ? '#i-pause' : '#i-play');
  }
  const sizeButton = document.querySelector('[data-radio="size"]');
  if (sizeButton) {
    sizeButton.setAttribute(
      'aria-label',
      radio.minimized ? 'Ampliar radio' : 'Minimizar radio'
    );
    sizeButton.title = radio.minimized
      ? 'Ampliar y reproducir'
      : 'Minimizar y pausar';
    sizeButton
      .querySelector('use')
      .setAttribute('href', radio.minimized ? '#i-expand' : '#i-collapse');
  }
  const stopButton = document.querySelector('[data-action="radio_stop"]');
  if (stopButton) stopButton.hidden = !radio.enabled;
  const status = document.querySelector('#radio-page-status');
  if (status) status.textContent = radio.message;
  const toggle = document.querySelector('#radio-toggle');
  if (toggle) {
    toggle.checked = radio.enabled;
    toggle.parentElement.lastChild.textContent = radio.enabled
      ? 'Radio activada'
      : 'Radio apagada';
  }
  document
    .querySelectorAll('[data-radio-song]')
    .forEach((row) =>
      row.classList.toggle(
        'selected',
        radio.enabled && radio.current?.id === row.dataset.radioSong
      )
    );
});
