'use strict';
(() => {
  const svg = (path) =>
    `<svg viewBox="0 0 24 24" aria-hidden="true">${path}</svg>`;
  const GLYPHS = {
    play: svg('<path d="m8 5 11 7-11 7Z"/>'),
    pause: svg('<path d="M8 5v14M16 5v14"/>'),
    sound: svg(
      '<path d="m11 5-6 5H2v4h3l6 5ZM15 8a6 6 0 0 1 0 8M18 5a10 10 0 0 1 0 14"/>'
    ),
    muted: svg('<path d="m11 5-6 5H2v4h3l6 5ZM16 9l5 6m0-6-5 6"/>'),
    full: svg('<path d="M4 9V4h5m6 0h5v5m0 6v5h-5m-6 0H4v-5"/>'),
  };
  const time = (seconds) => {
    const n = Math.max(0, Math.floor(Number(seconds) || 0));
    return n >= 3600
      ? `${Math.floor(n / 3600)}:${String(Math.floor(n / 60) % 60).padStart(2, '0')}:${String(n % 60).padStart(2, '0')}`
      : `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
  };
  class SeasonAV1PlayerController {
    constructor({ stage, iframe, episodeNumber = '', onThreshold, onStatus, onExtension, onPosition, onPreference, onEnded, resumePosition = 0, preferences = {} }) {
      this.stage = stage;
      this.onPosition = onPosition || (() => {});
      this.onPreference = onPreference || (() => {});
      this.onEnded = onEnded || (() => {});
      this.preferences = preferences;
      this.resumePosition = Number(resumePosition) || 0;
      this.resumePending = this.resumePosition > 0;
      this.resumeReady = !this.resumePending;
      this.preferencesApplied = false;
      if (this.resumePending) {
        this.resume = document.createElement('div'); this.resume.className='player-resume';
        this.resume.innerHTML=`<strong>Continuar desde ${time(this.resumePosition)}</strong><button type="button" data-resume="continue">Continuar</button><button type="button" data-resume="restart">Desde el inicio</button>`;
        stage.append(this.resume);
        this.resume.addEventListener('click',event=>{
          const action=event.target.closest('[data-resume]')?.dataset.resume;
          if(!action||!this.activated)return;
          this.resumePending=false;this.resumeTarget=action==='continue'?Math.min(this.resumePosition,this.latest.duration):0;
          this.post('seek',this.resumeTarget);this.resume.remove();this.post('play');
        });
      }
      this.iframe = iframe;
      this.onThreshold = onThreshold;
      this.onStatus = onStatus;
      this.onExtension = onExtension || (() => {});
      this.enhanced = false;
      this.closed = false;
      this.connected = false;
      this.activated = false;
      this.thresholdSent = false;
      this.episodeNumber = String(episodeNumber).trim().slice(0, 16);
      this.syncNoticeShown = false;
      this.latest = {
        position: 0,
        duration: 0,
        paused: true,
        volume: 1,
        muted: false,
      };
      this.timers = [];
      this.nonce = Array.from(crypto.getRandomValues(new Uint8Array(16)), (n) =>
        n.toString(16).padStart(2, '0')
      ).join('');
      this.bar = document.createElement('div');
      this.bar.className = 'season-video-ui';
      this.bar.hidden = true;
      this.bar.innerHTML = `<div class="video-seek"><div class="video-seek-track"><span class="video-buffered"></span><span class="video-played"></span></div><input class="video-progress" type="range" min="0" max="1000" step="1" value="0" aria-label="Posición del capítulo"><output class="video-seek-preview" aria-hidden="true" hidden>0:00</output></div><div class="video-button-row"><button type="button" data-video="toggle" title="Reproducir / pausar (Espacio)" aria-label="Reproducir">${GLYPHS.play}</button><button type="button" data-video="back" title="Retroceder 10 s (←)" aria-label="Retroceder diez segundos">−10</button><button type="button" data-video="forward" title="Adelantar 10 s (→)" aria-label="Adelantar diez segundos">+10</button><span class="video-time">0:00 / 0:00</span><button class="video-intro" type="button" data-video="intro" title="Adelantar 85 segundos" aria-label="Saltar intro, adelantar 85 segundos">Saltar intro <small>+85 s</small></button><span class="video-spacer"></span><button type="button" data-video="mute" title="Silenciar (M)" aria-label="Silenciar">${GLYPHS.sound}</button><input class="video-volume" type="range" min="0" max="1" step="0.05" value="1" aria-label="Volumen"><select class="video-rate" aria-label="Velocidad de reproducción" title="Velocidad de reproducción" hidden>${[0.5,0.75,1,1.25,1.5,1.75,2].map(n=>`<option value="${n}" ${n===1?'selected':''}>${n}×</option>`).join('')}</select><button type="button" data-video="fullscreen" title="Pantalla completa (F)" aria-label="Pantalla completa">${GLYPHS.full}</button></div>`;
      stage.append(this.bar);
      this.notice = document.createElement('div');
      this.notice.className = 'player-sync-toast';
      this.notice.hidden = true;
      this.notice.setAttribute('role', 'status');
      this.notice.setAttribute('aria-live', 'polite');
      this.notice.setAttribute('aria-atomic', 'true');
      this.notice.innerHTML = '<span class="player-sync-toast-icon" aria-hidden="true">✓</span><span class="player-sync-toast-text"></span>';
      stage.append(this.notice);
      this.listener = (e) => this.message(e);
      window.addEventListener('message', this.listener);
      this.click = (e) => this.handleClick(e);
      this.input = (e) => this.handleInput(e);
      this.key = (e) => this.handleKey(e);
      this.preview = (e) => this.previewTime(e);
      this.hidePreview = () => { this.bar.querySelector('.video-seek-preview').hidden = true; };
      this.reveal = () => this.show();
      this.fullscreen = () => this.show();
      this.bar.addEventListener('click', this.click);
      this.bar.addEventListener('input', this.input);
      this.bar.addEventListener('change', this.input);
      this.bar.addEventListener('focusin', this.reveal);
      this.bar.addEventListener('focusout', this.reveal);
      stage.addEventListener('pointermove', this.reveal, { passive: true });
      stage.addEventListener('pointerdown', this.reveal, { passive: true });
      this.bar.querySelector('.video-seek').addEventListener('pointermove', this.preview);
      this.bar.querySelector('.video-seek').addEventListener('pointerleave', this.hidePreview);
      document.addEventListener('keydown', this.key);
      document.addEventListener('fullscreenchange', this.fullscreen);
      this.onload = () => {
        if (!this.connected) this.connect();
      };
      iframe.addEventListener('load', this.onload);
      this.lifecycle = new MutationObserver(() => {
        if (!stage.isConnected) this.destroy();
      });
      this.lifecycle.observe(
        stage.closest('#dialog-body') || stage.parentElement,
        { childList: true }
      );
      this.connect();
      for (const delay of [1000, 3000, 7000])
        this.timers.push(
          setTimeout(() => {
            if (!this.connected) this.connect();
          }, delay)
        );
      this.timers.push(
        setTimeout(() => {
          if (!this.connected && !this.closed)
          {
            this.onExtension('missing');
            this.onStatus(
              'Instala o recarga la extensión de Brave para detectar el 80 % y sincronizar con MAL.',
              'unavailable', 'extension'
            );
          }
        }, 10000)
      );
    }
    post(type, value) {
      if (!this.closed)
        window.postMessage(
          {
            namespace: 'seasonav1.player.command/v1',
            type,
            nonce: this.nonce,
            value,
            ...(type === 'connect' ? { frame_url: this.iframe.src } : {}),
          },
          location.origin
        );
    }
    connect() {
      this.post('connect');
    }
    message(event) {
      const m = event.data;
      if (
        this.closed ||
        event.source !== window ||
        event.origin !== location.origin ||
        m?.namespace !== 'seasonav1.player.reply/v1' ||
        m.nonce !== this.nonce
      )
        return;
      if (m.type === 'installed') {
        this.onExtension('detected',m.payload);
        if (!this.connected)
          this.onStatus(
            'Extensión detectada. Esperando los datos del video…',
            'waiting'
          );
        return;
      }
      if (m.type === 'ready') {
        this.activated = false;
        this.connected = true;
        this.enhanced = m.payload?.controlsVersion >= 2;
        this.bar.querySelector('.video-rate').hidden = !this.enhanced;
        this.onExtension(this.enhanced ? 'ready' : 'update', m.payload);
        this.videoTimer=setTimeout(()=>{if(!this.activated&&!this.closed)this.onStatus('Extensión conectada; el servidor no entrega un video reproducible. Prueba otro servidor.','video');},30000);
        this.timers.forEach(clearTimeout);
        this.onStatus(
          'Extensión conectada. La marca se enviará al llegar al 80 %.',
          'connected'
        );
        return;
      }
      if (m.type === 'pointer') {
        this.show();
        return;
      }
      if (m.type === 'key' && m.payload?.key === 'f') {
        this.handleClick({ target: { closest: () => ({ dataset: { video: 'fullscreen' } }) } });
        return;
      }
      if (m.type === 'error') {
        this.onStatus(
          String(m.payload?.message || 'No se pudo controlar el video.'),
          'error', 'server'
        );
        return;
      }
      if (m.type !== 'state') return;
      const s = m.payload;
      if (
        !s ||
        typeof s.position !== 'number' ||
        typeof s.duration !== 'number' ||
        !Number.isFinite(s.position) ||
        !Number.isFinite(s.duration) ||
        s.position < 0 ||
        s.duration < 0 ||
        s.duration > 43200 ||
        s.position > s.duration + 1 ||
        typeof s.paused !== 'boolean'
      )
        return;
      const previousPaused = this.latest.paused;
      this.latest = s;
      const valid =
        s.videoReady === true && s.ad !== true && s.duration > 0 && !s.error;
      this.bar.hidden = !valid;
      if (!valid) {
        if (this.activated) {
          this.post('release');
          this.activated = false;
        }
        if (s.error)
          this.onStatus(
            'El servidor no pudo reproducir este video. Prueba abrir el servidor o cambiarlo.',
            'error'
          );
        return;
      }
      if (!this.activated) {
        this.post('activate');
        this.activated = true;
        this.connected = true;
        this.timers.forEach(clearTimeout);
        this.onStatus(
          `Detección activa · se marcará al llegar a ${time(s.duration * 0.8)} (80 %).`,
          'connected'
        );
      }
      clearTimeout(this.videoTimer);
      if(!this.preferencesApplied){
        this.preferencesApplied=true;
        if(Number.isFinite(this.preferences.volume))this.post('volume',this.preferences.volume);
        if(this.preferences.muted===true && s.muted!==true)this.post('mute');
        if(this.enhanced && Number.isFinite(this.preferences.rate))this.post('rate',this.preferences.rate);
        if(this.resumePending)this.post('pause');
      }
      if(!this.resumePending && !this.resumeReady && Math.abs(s.position-this.resumeTarget)<2)this.resumeReady=true;
      if(this.resumeReady){this.onPosition(s);if(s.ended===true&&s.position>=s.duration-2&&!this.endedSent){this.endedSent=true;this.onEnded();}}
      const seek = this.bar.querySelector('.video-progress');
      if (document.activeElement !== seek)
        seek.value = String(Math.round((s.position / s.duration) * 1000));
      seek.setAttribute(
        'aria-valuetext',
        `${time(s.position)} de ${time(s.duration)}`
      );
      this.bar.querySelector('.video-played').style.width = `${(s.position / s.duration) * 100}%`;
      // Render disjoint buffered ranges, including buffers after a seek.
      const buffers = Array.isArray(s.buffered) ? s.buffered.slice(0, 32) : [];
      const stops = buffers.filter(r=>Array.isArray(r)&&r.length===2&&r.every(Number.isFinite)&&r[0]>=0&&r[1]>=r[0]&&r[1]<=s.duration+1)
        .flatMap(r=>[`transparent ${r[0]/s.duration*100}%`, `#ffffff65 ${r[0]/s.duration*100}%`, `#ffffff65 ${Math.min(r[1]/s.duration,1)*100}%`, `transparent ${Math.min(r[1]/s.duration,1)*100}%`]);
      this.bar.querySelector('.video-buffered').style.background = stops.length ? `linear-gradient(to right, transparent 0%, ${stops.join(', ')}, transparent 100%)` : 'transparent';
      const rate = this.bar.querySelector('.video-rate');
      if (document.activeElement !== rate && Number.isFinite(s.playbackRate)) rate.value = String(s.playbackRate);
      this.bar.querySelector('.video-time').textContent =
        `${time(s.position)} / ${time(s.duration)}`;
      const toggle = this.bar.querySelector('[data-video="toggle"]');
      toggle.innerHTML = s.paused ? GLYPHS.play : GLYPHS.pause;
      toggle.setAttribute('aria-label', s.paused ? 'Reproducir' : 'Pausar');
      const mute = this.bar.querySelector('[data-video="mute"]');
      mute.innerHTML = s.muted ? GLYPHS.muted : GLYPHS.sound;
      mute.setAttribute('aria-label', s.muted ? 'Activar sonido' : 'Silenciar');
      if (document.activeElement !== this.bar.querySelector('.video-volume'))
        this.bar.querySelector('.video-volume').value = String(
          s.muted ? 0 : s.volume
        );
      if (s.paused || previousPaused) this.show();
      if (this.resumeReady && s.position / s.duration >= 0.8 && !this.thresholdSent)
        this.scrobble(s);
    }
    scrobble(s) {
      if (!this.closed && !this.thresholdSent) {
        this.thresholdSent = true;
        this.onStatus('80 % alcanzado. Guardando el capítulo visto…', 'saving');
        Promise.resolve(
          this.onThreshold({ position: s.position, duration: s.duration })
        )
          .then((result) => {
            if (!this.closed && result) {
              this.onStatus(result.message, result.state);
              if (result.state === 'synced') this.notifySynced();
            }
          })
          .catch(() => {
            if (this.closed) return;
            this.onStatus(
              'No se pudo guardar. Se reintentará con la posición ya detectada.',
              'error','mal'
            );
            this.retryTimer = setTimeout(() => {
              this.thresholdSent = false;
              this.scrobble(s);
            }, 30000);
          });
      }
    }
    notifySynced() {
      if (this.closed || this.syncNoticeShown || !this.stage.isConnected) return;
      this.syncNoticeShown = true;
      this.notice.querySelector('.player-sync-toast-text').textContent =
        `Capítulo${this.episodeNumber ? ' ' + this.episodeNumber : ''} actualizado en MyAnimeList`;
      this.notice.style.setProperty('--notice-controls-height', `${this.bar.offsetHeight || 112}px`);
      this.notice.hidden = false;
      this.notice.classList.add('is-visible');
      this.noticeTimer = setTimeout(() => {
        this.notice.classList.remove('is-visible');
        this.notice.classList.add('is-leaving');
        this.noticeExitTimer = setTimeout(() => {
          this.notice.hidden = true;
          this.notice.classList.remove('is-leaving');
        }, 200);
      }, 4200);
    }
    show() {
      if (this.closed) return;
      this.stage.classList.remove('video-controls-hidden');
      clearTimeout(this.hideTimer);
      this.hideTimer = null;
      if (!this.latest.paused)
        this.hideTimer = setTimeout(() => {
          this.hideTimer = null;
          if (
            this.bar.contains(document.activeElement) &&
            document.activeElement.matches(':focus-visible')
          )
            return;
          this.stage.classList.add('video-controls-hidden');
        }, 2800);
    }
    handleInput(event) {
      this.show();
      const t = event.target;
      if (event.type !== 'change' && t.matches('.video-progress') && this.latest.duration > 0)
        this.post('seek', (Number(t.value) / 1000) * this.latest.duration);
      if (event.type !== 'change' && t.matches('.video-volume')) {this.post('volume', Number(t.value));this.onPreference({volume:Number(t.value),muted:false});}
      if (event.type === 'change' && t.matches('.video-rate') && this.enhanced) {this.post('rate', Number(t.value));this.onPreference({rate:Number(t.value)});}
    }
    previewTime(event) {
      if (this.latest.duration <= 0) return;
      const rect = this.bar.querySelector('.video-progress').getBoundingClientRect();
      if (!rect.width) return;
      const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
      const tip = this.bar.querySelector('.video-seek-preview');
      tip.textContent = time(ratio * this.latest.duration);
      tip.style.left = `${Math.max(24, Math.min(rect.width - 24, ratio * rect.width))}px`;
      tip.hidden = false;
      this.show();
    }
    handleKey(event) {
      if (this.closed || !this.activated || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || event.target?.closest('input,select,textarea,button,a,[contenteditable="true"]')) return;
      const key = event.key.toLowerCase();
      const action = { ' ': 'toggle', k: 'toggle', arrowleft: 'back', arrowright: 'forward', f: 'fullscreen', m: 'mute' }[key];
      if (!action) return;
      event.preventDefault();
      if (event.repeat && ['toggle','fullscreen','mute'].includes(action)) return;
      this.handleClick({ target: { closest: () => ({ dataset: { video: action } }) } });
    }
    async handleClick(event) {
      const action = event.target.closest('[data-video]')?.dataset.video;
      if (!action) return;
      this.show();
      if (action === 'toggle') this.post(this.latest.paused ? 'play' : 'pause');
      if (action === 'back' || action === 'forward' || action === 'intro')
        this.post(
          'seek',
          Math.max(
            0,
            Math.min(
              this.latest.duration,
              this.latest.position + (action === 'back' ? -10 : action === 'intro' ? 85 : 10)
            )
          )
        );
      if (action === 'mute') {this.post('mute');this.onPreference({muted:!this.latest.muted});}
      if (action === 'fullscreen') {
        try {
          if (document.fullscreenElement === this.stage)
            await document.exitFullscreen();
          else await this.stage.requestFullscreen();
        } catch {
          this.onStatus(
            'El navegador no permitió la pantalla completa.',
            'error'
          );
        }
      }
    }
    destroy() {
      if (this.closed) return;
      if(this.resumeReady && this.latest.duration>0)this.onPosition(this.latest,true);
      this.resume?.remove();clearTimeout(this.videoTimer);
      this.post('disconnect');
      this.closed = true;
      this.timers.forEach(clearTimeout);
      clearTimeout(this.hideTimer);
      clearTimeout(this.retryTimer);
      clearTimeout(this.noticeTimer);
      clearTimeout(this.noticeExitTimer);
      this.lifecycle.disconnect();
      window.removeEventListener('message', this.listener);
      this.iframe.removeEventListener('load', this.onload);
      this.bar.removeEventListener('click', this.click);
      this.bar.removeEventListener('input', this.input);
      this.bar.removeEventListener('change', this.input);
      this.bar.removeEventListener('focusin', this.reveal);
      this.bar.removeEventListener('focusout', this.reveal);
      this.stage.removeEventListener('pointermove', this.reveal);
      this.stage.removeEventListener('pointerdown', this.reveal);
      document.removeEventListener('fullscreenchange', this.fullscreen);
      document.removeEventListener('keydown', this.key);
      this.bar.querySelector('.video-seek').removeEventListener('pointermove', this.preview);
      this.bar.querySelector('.video-seek').removeEventListener('pointerleave', this.hidePreview);
      this.bar.remove();
      this.notice.remove();
    }
  }
  globalThis.SeasonAV1PlayerController = SeasonAV1PlayerController;
})();
