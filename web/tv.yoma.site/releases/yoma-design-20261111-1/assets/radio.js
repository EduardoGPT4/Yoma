'use strict';
class AnimeRadio {
  constructor() {
    this.tracks = [];
    this.enabled = false;
    this.minimized = false;
    this.index = 0;
    this.type = 'all';
    this.player = null;
    this.ready = false;
    this.generation = 0;
    this.playing = false;
    this.message = 'Radio apagada';
    this.skipped = new Set();
    try {
      this.volume = Math.max(
        0,
        Math.min(
          100,
          Number(localStorage.getItem('seasonav1.radio.volume') ?? 50)
        )
      );
    } catch (_) {
      this.volume = 50;
    }
    document.addEventListener('visibilitychange', () => {
      if (document.hidden)
        this.pause('En pausa mientras la pestaña está oculta.');
    });
  }
  setTracks(data) {
    this.data = {...data,tracks:data.tracks.filter(t=>t.quality_status!=='review')};
    this.tracks = this.data.tracks;
  }
  get current() {
    return this.tracks[this.index];
  }
  playlist() {
    return this.tracks
      .map((t, i) => ({ t, i }))
      .filter(({ t }) => this.type === 'all' || t.type === this.type);
  }
  notify() {
    document.dispatchEvent(new CustomEvent('season-radio-change'));
  }
  status(message) {
    this.message = message;
    const el = document.querySelector('#radio-status');
    if (el) el.textContent = message;
    this.notify();
  }
  async api() {
    if (window.YT?.Player) return;
    if (!AnimeRadio.loading)
      AnimeRadio.loading = new Promise((resolve, reject) => {
        const previous = window.onYouTubeIframeAPIReady;
        const timer = setTimeout(() => {
          document.querySelector('script[data-youtube-api]')?.remove();
          AnimeRadio.loading = null;
          reject(
            new Error(
              'YouTube no respondió. Puedes reintentar o abrir la canción en YouTube.'
            )
          );
        }, 15000);
        window.onYouTubeIframeAPIReady = () => {
          clearTimeout(timer);
          previous?.();
          resolve();
        };
        let script = document.querySelector('script[data-youtube-api]');
        if (!script) {
          script = document.createElement('script');
          script.src = 'https://www.youtube.com/iframe_api';
          script.dataset.youtubeApi = 'true';
          document.head.append(script);
        }
        script.onerror = () => {
          clearTimeout(timer);
          script.remove();
          AnimeRadio.loading = null;
          reject(new Error('El navegador bloqueó el reproductor de YouTube.'));
        };
      });
    await AnimeRadio.loading;
  }
  dock() {
    const root = document.querySelector('#radio-dock'),
      t = this.current;
    const scroll = window.scrollY || 0;
    root.hidden = false;
    document.body.classList.add('radio-enabled');
    root.innerHTML = `<div class="radio-dock-heading"><span class="online-dot"></span><strong>YomaTV Radio · YouTube</strong><button class="icon-button" data-radio="size" aria-label="Minimizar radio" title="Minimizar y pausar"><svg><use href="#i-collapse"/></svg></button><button class="icon-button" data-radio="off" aria-label="Apagar radio"><svg><use href="#i-close"/></svg></button></div><div id="youtube-player"></div><div class="radio-track-info"><strong id="radio-track-title"></strong><span id="radio-track-anime"></span><a id="radio-youtube-link" target="_blank" rel="noopener noreferrer">Ver en YouTube ↗</a></div><div class="radio-controls"><button class="button small ghost" data-radio="previous" aria-label="Canción anterior">‹</button><button class="button small primary" data-radio="play" aria-label="Reproducir"><svg><use href="#i-play"/></svg><span>Reproducir</span></button><button class="button small ghost" data-radio="next" aria-label="Siguiente canción">›</button><label>Vol.<input id="radio-volume" aria-label="Volumen de la radio" type="range" min="0" max="100" value="${this.volume}"></label></div><p id="radio-status" role="status"></p>`;
    const main = document.querySelector('#main');
    if (main?.scrollTo) {
      window.scrollTo({ top: 0 });
      main.scrollTo({ top: Math.max(0, scroll - main.offsetTop) });
    }
    this.updateTrack();
  }
  updateTrack() {
    const t = this.current;
    if (!t) return;
    document.querySelector('#radio-track-title').textContent = t.title;
    document.querySelector('#radio-track-anime').textContent =
      `${t.anime} · ${t.artist}`;
    document.querySelector('#radio-youtube-link').href = t.url;
  }
  async start(id) {
    if (!this.tracks.length) return;
    this.expand();
    if (id) {
      const i = this.tracks.findIndex((t) => t.id === id);
      if (i >= 0) this.index = i;
    }
    if (!this.playlist().some(({ i }) => i === this.index))
      this.index = this.playlist()[0]?.i ?? 0;
    this.skipped.clear();this.errorStreak=0;
    if (this.player) {
      this.updateTrack();
      if (this.ready) this.player.loadVideoById(this.current.id);
      this.status('Cargando canción…');
      return;
    }
    this.enabled = true;
    const generation = ++this.generation;
    this.dock();
    this.status('Conectando con YouTube…');
    try {
      await this.api();
      if (!this.enabled || generation !== this.generation) return;
      this.player = new YT.Player('youtube-player', {
        host: 'https://www.youtube-nocookie.com',
        width: '100%',
        height: 200,
        videoId: this.current.id,
        playerVars: { playsinline: 1, origin: location.origin, autoplay: 0 },
        events: {
          onReady: (event) => {
            if (!this.enabled || generation !== this.generation) {
              event.target.destroy();
              return;
            }
            this.ready = true;
            event.target.setVolume(this.volume);
            if (
              !this.minimized &&
              !document.hidden &&
              !document.querySelector('#dialog').open
            )
              event.target.loadVideoById(this.current.id);
            this.status(
              this.minimized
                ? 'Minimizada · amplía la radio para escuchar.'
                : 'Pulsa Reproducir si tu navegador solicita interacción.'
            );
          },
          onStateChange: (event) => {
            if (generation !== this.generation) return;
            this.playing = event.data === 1;
            if (event.data === 1) {
              this.skipped.clear();this.errorStreak=0;
              if (
                this.minimized ||
                document.hidden ||
                document.querySelector('#dialog').open
              )
                this.pause('En pausa.');
              else this.status('Reproduciendo en YouTube');
            } else if (event.data === 0) {
              this.next(1, true);
            } else if (event.data === 2)
              this.status(
                this.minimized
                  ? 'Minimizada · amplía la radio para escuchar.'
                  : 'En pausa · pulsa Reproducir para continuar.'
              );
          },
          onError: (event) => {
            if (generation !== this.generation) return;
            this.skipped.add(this.current.id);
            this.playing = false;
            this.status(
              `YouTube no permite este video (${event.data}). Pulsa Siguiente o ábrelo en YouTube.`
            );
            this.unavailable?.();
          },
          onAutoplayBlocked: () =>
            this.status('Pulsa Reproducir para iniciar la canción.')
        }
      });
    } catch (error) {
      this.status(error.message);
    }
  }
  pause(message = 'En pausa.') {
    if (this.enabled) {
      if (this.ready) this.player?.pauseVideo?.();
      this.playing = false;
      this.status(message);
    }
  }
  expand() {
    this.minimized = false;
    document.body.classList.remove('radio-minimized');
    this.notify();
  }
  minimize() {
    if (!this.enabled) return;
    this.pause('Minimizada · amplía la radio para escuchar.');
    this.minimized = true;
    document.body.classList.add('radio-minimized');
    this.notify();
  }
  play() {
    if (!this.enabled) {
      return this.start();
    }
    if (this.minimized) this.expand();
    if (!this.player) {
      return this.start(this.current.id);
    }
    if (this.playing) this.pause();
    else if (
      this.ready &&
      !document.hidden &&
      !document.querySelector('#dialog').open
    )
      this.player.playVideo();
  }
  next(direction = 1, automatic = false) {
    const list = this.playlist();
    if (!list.length) return;
    if (
      automatic &&
      (this.minimized ||
        document.hidden ||
        document.querySelector('#dialog').open)
    ) {
      this.pause();
      return;
    }
    if (!automatic && this.minimized) this.expand();
    const position = list.findIndex(({ i }) => i === this.index);
    this.index = list[(position + direction + list.length) % list.length].i;
    if (this.enabled && this.player) {
      this.updateTrack();
      if (this.ready) this.player.loadVideoById(this.current.id);
      this.status('Cargando canción…');
    } else if (!automatic) this.start(this.current.id);
  }
  setVolume(volume) {
    this.volume = Math.max(0, Math.min(100, Number(volume)));
    if (this.ready) this.player?.setVolume?.(this.volume);
    try {
      localStorage.setItem('seasonav1.radio.volume', String(this.volume));
    } catch (_) {}
  }
  off() {
    const scroll = document.querySelector('#main')?.scrollTop || 0;
    ++this.generation;
    this.player?.destroy?.();
    this.player = null;
    this.ready = false;
    this.enabled = false;
    this.minimized = false;
    this.playing = false;
    const root = document.querySelector('#radio-dock');
    root.hidden = true;
    root.replaceChildren();
    document.body.classList.remove('radio-enabled', 'radio-minimized');
    if (scroll && window.requestAnimationFrame)
      window.requestAnimationFrame(() => window.scrollTo({ top: scroll }));
    this.status('Radio apagada');
  }
}
window.AnimeRadio = AnimeRadio;
