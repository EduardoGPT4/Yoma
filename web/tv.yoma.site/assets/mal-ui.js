'use strict';
let malListPage = null;
const MAL_STATUSES = {
  watching: 'Viendo',
  completed: 'Completado',
  on_hold: 'En pausa',
  dropped: 'Abandonado',
  plan_to_watch: 'Por ver',
  unknown: 'Sin estado',
};

function malAccountPanel() {
  const mal = accountInfo?.mal,
    profile = mal?.profile;
  const connected = !!mal?.connected,
    ready = !!mal?.configured;
  return `<section class="panel account-mal"><div class="mal-heading"><span class="mal-logo" aria-hidden="true">MAL</span><div><h2>MyAnimeList</h2><p>Tu perfil y tu lista, conectados.</p></div><span class="status-pill ${connected ? 'confirmed' : 'pending'}">${connected ? 'Conectado' : mal?.needs_auth ? 'Reconectar' : 'Sin conectar'}</span></div>
    ${!mal ? '<p>Consultando conexión…</p>' : connected ? `<div class="mal-profile"><strong>${e(profile.name)}</strong><a href="${e(profile.url)}" target="_blank" rel="noopener noreferrer">Abrir perfil en MAL ↗</a><span>Última comprobación: ${e(new Date(profile.checked_at * 1000).toLocaleString('es-MX'))}</span></div>` : `<p>${mal.needs_auth ? 'MyAnimeList retiró el permiso. Autoriza la cuenta otra vez para recuperar la conexión.' : ready ? 'Autoriza desde MyAnimeList para consultar tus animes, estados, puntuaciones y capítulos vistos.' : 'La conexión con MyAnimeList aún no está configurada en el servidor.'}</p>`}
    <div class="toolbar">${connected ? button('mal_list', 'Consultar mi lista', 'library', '', 'primary') + button('mal_profile', 'Comprobar conexión', 'refresh', '', 'ghost') : `<button class="button primary" data-action="mal_connect" ${!ready ? 'disabled' : ''}>${icon('arrow')}${mal?.needs_auth ? 'Reconectar MyAnimeList' : 'Conectar MyAnimeList'}</button>`}${profile ? button('mal_disconnect_prompt', 'Desvincular', 'close', '', 'ghost') : ''}</div><p class="mal-privacy">La autorización ocurre en MyAnimeList. Puedes consultar y editar tu lista desde Mi lista MAL. Guardar en MyAnimeList y alcanzar el 80 % del capítulo sincronizan tu progreso. Retirar de MAL elimina la entrada y detiene sus envíos pendientes.</p>
  </section>`;
}

function showMalList(page) {
  malListPage = { user: state.user.id, ...page };
  const count = page.items.length;
  modal(
    `<div class="mal-list"><p class="eyebrow">MI LISTA · MYANIMELIST</p><h2>Las historias que llevas contigo.</h2><p class="muted">${count ? `Animes ${page.offset + 1}–${page.offset + count}.` : 'Tu lista está vacía.'} Estados y progreso guardados en MAL.</p><div class="mal-list-items">${page.items.map((item) => `<article class="mal-list-item"><div><a href="${e(item.url)}" target="_blank" rel="noopener noreferrer">${e(item.title)} ↗</a><span>${e(MAL_STATUSES[item.status] || MAL_STATUSES.unknown)} · ${item.watched} capítulos vistos</span></div><span class="mal-score">${item.score ? `${item.score}/10` : 'Sin nota'}</span></article>`).join('')}</div><div class="toolbar mal-pagination">${page.offset ? button('mal_prev', 'Anterior', 'arrow', '', 'ghost') : ''}<span>Página ${page.offset / 50 + 1}</span>${page.has_more ? button('mal_next', 'Siguiente', 'arrow', '', 'primary') : ''}</div><small class="muted">Consulta de tu lista de MAL. Los enlaces abren la ficha original.</small></div>`
  );
}

document.addEventListener('click', async (event) => {
  const control = event.target.closest('[data-action]'),
    action = control?.dataset.action;
  if (
    ![
      'mal_connect',
      'mal_profile',
      'mal_list',
      'mal_prev',
      'mal_next',
      'mal_disconnect_prompt',
      'mal_disconnect',
    ].includes(action)
  )
    return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (control.disabled || !requireUser()) return;
  const user = state.user.id, interaction = dialogTicket();
  control.disabled = true;
  try {
    if (action === 'mal_connect') {
      const result = await api('mal_connect');
      if (state.user?.id !== user || !dialogCurrent(interaction)) return;
      const url = new URL(result.authorization_url);
      if (
        url.origin !== 'https://myanimelist.net' ||
        url.pathname !== '/v1/oauth2/authorize'
      )
        throw new Error('No se recibió un enlace de autorización válido.');
      location.assign(url.href);
    } else if (action === 'mal_disconnect_prompt') {
      modal(
        `<div class="auth-form"><p class="eyebrow">MYANIMELIST</p><h2>¿Desvincular esta cuenta?</h2><p>Se borrarán los tokens guardados en esta web. Tu biblioteca y tu lista de MAL se conservan. Puedes retirar el permiso también en las aplicaciones autorizadas de MyAnimeList.</p><div class="toolbar">${button('mal_disconnect', 'Desvincular MyAnimeList', 'close', '', 'primary')}${button('close', 'Conservar conexión', '', '', 'ghost')}</div></div>`
      );
    } else if (action === 'mal_disconnect') {
      const result = await api(action);
      if (state.user?.id !== user) return;
      accountInfo = { ...accountInfo, mal: result.mal };
      malListPage = null;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      render();
      toast(result.message);
    } else {
      const offset =
        action === 'mal_prev' || action === 'mal_next'
          ? malListPage?.user === user
            ? malListPage.offset + (action === 'mal_next' ? 50 : -50)
            : 0
          : 0;
      const result = await api(action === 'mal_profile' ? action : 'mal_list', {
        offset,
      });
      if (state.user?.id !== user) return;
      accountInfo = { ...accountInfo, mal: result.mal };
      if (result.mal_list && dialogCurrent(interaction)) showMalList(result.mal_list);
      else {
        render();
        toast(result.message);
      }
    }
  } catch (error) {
    toast(error.message, true);
    if (state.user?.id === user) {
      accountInfo = null;
      if (view === 'account') render();
    }
  } finally {
    control.disabled = false;
  }
});

function showMalCallbackNotice() {
  const url = new URL(location.href);
  if (!url.searchParams.has('mal')) return;
  url.searchParams.delete('mal');
  history.replaceState(null, '', url.pathname + url.search + url.hash);
}

function showMalServerNotice(result) {
  const notices = {
    connected:
      'MyAnimeList conectado. Ya puedes consultar tu lista desde Mi cuenta.',
    account_changed:
      'Cuenta MAL actualizada. Se detuvieron los envíos anteriores; tu biblioteca web se conserva y se renovará la lista conectada.',
    denied:
      'Autorización cancelada. Tu cuenta de MyAnimeList no se ha cambiado.',
    expired:
      'La autorización no es válida o caducó. Conecta MyAnimeList de nuevo.',
    error:
      'No se pudo conectar con MyAnimeList. Intenta de nuevo en unos minutos.',
  };
  if (!Object.hasOwn(notices, result)) return;
  toast(notices[result], result === 'error' || result === 'expired');
}
