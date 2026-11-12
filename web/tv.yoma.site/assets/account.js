'use strict';
let accountInfo = null,
  accountBusy = false,
  accountError = '',
  recoveryDisplay = null,
  libraryImportPreview = null;
function accountStateChanged() {
  if (typeof detailDrafts !== 'undefined') detailDrafts.clear();
  if (typeof queueHistoryLoads !== 'undefined') queueHistoryLoads.clear();
  catalogSequence++;
  catalogState = null;
  clearTimeout(catalogTimer);
  queueMicrotask(() => { if (state && view==='discover') loadCatalog(); });
  if (typeof resetFeatures === 'function') resetFeatures();
  accountInfo = null;
  accountError = '';
  recoveryDisplay = null;
  libraryImportPreview = null;
  if (typeof malListPage !== 'undefined') malListPage = null;
}

function securityField(
  prefix,
  name,
  label,
  autocomplete = 'current-password',
  extra = ''
) {
  const id = `${prefix}-${name}`;
  return `<div class="field"><label for="${id}">${e(label)}</label><input class="form-input" id="${id}" name="${name}" type="password" autocomplete="${autocomplete}" maxlength="${name === 'current_password' ? 200 : 72}" ${extra} required></div>`;
}
function passwordFields(prefix) {
  return (
    securityField(
      prefix,
      'new_password',
      'Contraseña nueva',
      'new-password',
      'minlength="8"'
    ) +
    securityField(
      prefix,
      'password_confirm',
      'Repite la contraseña nueva',
      'new-password',
      'minlength="8"'
    )
  );
}
function accountView() {
  const intro = title(
    'TU CUENTA',
    'Tu biblioteca, bajo tu control.',
    'Guarda una copia, configura la recuperación y protege tu acceso.'
  );
  if (!state.user)
    return (
      intro +
      empty(
        'Inicia sesión para gestionar tu cuenta',
        'Tus datos se guardan en tu cuenta de SeasonAV1 Web.',
        button('account', 'Iniciar sesión', 'pc', '', 'primary')
      )
    );
  if (accountError)
    return (
      intro +
      empty(
        'No se pudo consultar tu cuenta',
        accountError,
        button('account_retry', 'Reintentar', 'refresh', '', 'primary')
      )
    );
  if (!accountInfo && !accountBusy) loadAccount();
  const remaining = accountInfo
    ? `${accountInfo.recovery_remaining} códigos disponibles`
    : 'Consultando códigos…';
  return (
    intro +
    `<div class="account-identity"><div class="avatar">${e(state.user.name.slice(0, 1).toUpperCase())}</div><div><strong>${e(state.user.name)}</strong><span>${e(state.user.email)}</span></div>${state.user.is_admin ? '<span class="status-pill confirmed">Administrador</span>' : ''}${button('logout', 'Cerrar sesión', 'arrow', '', 'ghost')}</div>${typeof malAccountPanel === 'function' ? malAccountPanel() : ''}<div class="account-grid">
    <section class="panel"><h2 class="panel-title">${icon('pc')}Cambiar contraseña</h2><p>Usa al menos 8 caracteres. Las demás sesiones se cerrarán al cambiarla.</p><form id="account-password-form">${securityField('password', 'current_password', 'Contraseña actual')}${passwordFields('password')}<p class="form-error" aria-live="polite"></p><button class="button primary" type="submit">Guardar contraseña</button></form></section>
    <section class="panel"><h2 class="panel-title">${icon('check')}Recuperar tu acceso</h2><p>Guarda los códigos en un lugar seguro. Cada uno permite recuperar la cuenta una sola vez.</p><div class="account-code-count">${e(remaining)}</div><form id="account-codes-form">${securityField('codes', 'current_password', 'Confirma tu contraseña actual')}<p class="form-error" aria-live="polite"></p><button class="button ghost" type="submit">${accountInfo?.recovery_remaining ? 'Renovar códigos' : 'Generar 10 códigos'}</button><small>Renovar los códigos invalida los anteriores.</small></form></section>
    <section class="panel account-library"><h2 class="panel-title">${icon('library')}Copias de tu biblioteca</h2><p>El JSON conserva estados, favoritos, exclusiones, notas, puntuaciones y capítulos vistos.</p><div class="toolbar">${button('account_export', 'Exportar biblioteca', 'download', '', 'primary')}${button('account_import', 'Importar JSON', 'upload', '', 'ghost')}</div><input type="file" id="library-file" accept="application/json,.json" hidden><p class="muted">Al importar, los animes coincidentes reciben los valores del archivo. Los demás animes y los capítulos que ya marcaste como vistos se conservan.</p></section>
    <section class="panel account-delete"><h2 class="panel-title">${icon('close')}Eliminar cuenta</h2><p>Elimina tu biblioteca, preferencias, historial y registro de descargas de esta web. Los videos de tu PC permanecen en su carpeta.</p>${state.user.is_admin ? '<p class="account-admin-note">Esta cuenta administra el sitio. Asigna otra cuenta administradora antes de eliminarla.</p>' : button('account_delete', 'Eliminar mi cuenta', 'close', '', 'danger')}</section>
  </div>`
  );
}
async function loadAccount() {
  if (!state.user || accountBusy) return;
  accountBusy = true;
  const user = state.user.id;
  try {
    const result = await api('account', {}, true);
    if (state.user?.id === user) {
      accountInfo = result.account;
      if (typeof showMalServerNotice === 'function')
        showMalServerNotice(result.account.mal_notice);
    }
  } catch (error) {
    accountError = error.message;
  } finally {
    accountBusy = false;
    if (view === 'account') render();
  }
}
function openAccount() {
  if (!requireUser()) return;
  $('#dialog').close();
  navigate('account');
}

function showAuth(mode = authMode) {
  authMode = mode;
  if (state?.user) {
    openAccount();
    return;
  }
  modal(
    `<div class="auth-form"><p class="eyebrow">BIENVENIDO A SEASONAV1</p><h2>Un lugar para tus historias.</h2><p>Guarda tu temporada y continúa desde cualquier dispositivo.</p><div class="auth-switch"><button class="${mode === 'login' ? 'active' : ''}" data-action="auth_login">Iniciar sesión</button><button class="${mode === 'register' ? 'active' : ''}" data-action="auth_register">Crear cuenta</button></div><form id="auth-form" data-mode="${mode}">${mode === 'register' ? '<div class="field"><label for="auth-name">Tu nombre</label><input id="auth-name" class="form-input" name="name" autocomplete="name" minlength="2" maxlength="60" required></div>' : ''}<div class="field"><label for="auth-email">Correo</label><input id="auth-email" class="form-input" name="email" type="email" autocomplete="email" maxlength="190" required></div><div class="field"><label for="auth-password">Contraseña</label><input id="auth-password" class="form-input" name="password" type="password" autocomplete="${mode === 'register' ? 'new-password' : 'current-password'}" minlength="${mode === 'register' ? 8 : 1}" maxlength="${mode === 'register' ? 72 : 200}" required></div><p class="form-error" id="auth-error" aria-live="polite"></p><button type="submit" class="button primary wide">${e(mode === 'register' ? 'Crear mi biblioteca' : 'Entrar a mi temporada')}${icon('arrow')}</button></form>${mode === 'login' ? button('auth_recover', 'Olvidé mi contraseña', '', '', 'text-button auth-recovery-link') : '<p class="muted">Después de crear la cuenta, guarda tus códigos de recuperación en Mi cuenta.</p>'}</div>`
  );
}
function showRecovery() {
  modal(
    `<div class="auth-form"><p class="eyebrow">RECUPERAR MI CUENTA</p><h2>Vuelve a tu biblioteca.</h2><p>Necesitas uno de los códigos que guardaste en Mi cuenta.</p><form id="account-recover-form"><div class="field"><label for="recover-email">Correo de tu cuenta</label><input class="form-input" id="recover-email" type="email" name="email" autocomplete="email" maxlength="190" required></div><div class="field"><label for="recover-code">Código de recuperación</label><input class="form-input" id="recover-code" name="recovery_code" autocomplete="off" maxlength="50" spellcheck="false" required></div>${passwordFields('recover')}<p class="form-error" aria-live="polite"></p><button class="button primary wide" type="submit">Recuperar cuenta</button></form><p class="muted">Cada código se consume al recuperar la cuenta. Si aún no configuraste códigos, este método no puede recuperar tu acceso.</p>${button('auth_login', 'Volver a iniciar sesión', 'arrow', '', 'ghost')}</div>`
  );
}
function showRecoveryCodes(codes) {
  recoveryDisplay = { user: state.user.id, codes };
  modal(
    `<div class="recovery-codes"><p class="eyebrow">GUÁRDALOS AHORA</p><h2>Tus 10 códigos de recuperación.</h2><p>Se muestran una sola vez. Guárdalos antes de cerrar; cada código se puede usar una sola vez.</p><ol class="recovery-code-list">${codes.map((code) => `<li><code>${e(code)}</code></li>`).join('')}</ol><div class="toolbar">${button('account_save_codes', 'Guardar códigos TXT', 'download', '', 'primary')}${button('close', 'Ya los guardé', 'check', '', 'ghost')}</div></div>`
  );
}
function saveAccountFile(value, name, type = 'application/json') {
  const blob = new Blob(
    [typeof value === 'string' ? value : JSON.stringify(value, null, 2)],
    { type }
  );
  const url = URL.createObjectURL(blob),
    link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

document.addEventListener('click', async (event) => {
  const control = event.target.closest('[data-action]');
  const action = control?.dataset.action;
  if (
    ![
      'auth_recover',
      'account_retry',
      'account_export',
      'account_import',
      'account_import_confirm',
      'account_save_codes',
      'account_delete',
    ].includes(action)
  )
    return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (control.disabled) return;
  control.disabled = true;
  try {
    if (action === 'auth_recover') {
      showRecovery();
      return;
    }
    if (action === 'account_retry') {
      accountError = '';
      render();
      return;
    }
    if (!requireUser()) return;
    const user = state.user.id;
    if (action === 'account_export') {
      const result = await api('library_export', {}, true);
      if (state.user?.id !== user) return;
      libraryImportChunks(result.library);
      const serialized = JSON.stringify(result.library, null, 2);
      if (new Blob([serialized]).size > LIBRARY_FILE_LIMIT) throw new Error('La biblioteca supera 128 MB. Divide la copia antes de restaurarla.');
      saveAccountFile(
        serialized,
        `SeasonAV1-biblioteca-${result.library.exported_at.slice(0, 10)}.json`
      );
      toast('Biblioteca exportada.');
    } else if (action === 'account_import') $('#library-file').click();
    else if (action === 'account_import_confirm') {
      const preview = libraryImportPreview;
      if (!preview)
        throw new Error('Selecciona de nuevo el archivo de biblioteca.');
      const interaction = dialogTicket();
      for (; preview.next < preview.parts.length; preview.next++) {
        if (state.user?.id !== user || !dialogCurrent(interaction, true)) return;
        const progress = document.querySelector('[data-library-import-progress]');
        if (progress) progress.textContent = `Importando ${preview.next + 1} de ${preview.parts.length}…`;
        const result = await api('library_import', { library: preview.parts[preview.next],
          batch: { id: preview.id, index: preview.next, total: preview.parts.length } });
        for (const key of Object.keys(preview.imported)) preview.imported[key] += result.imported[key];
      }
      if (state.user?.id !== user) return;
      if (dialogCurrent(interaction, true)) $('#dialog').close();
      if (libraryImportPreview === preview) libraryImportPreview = null;
      render();
      const skipped =
        preview.imported.unknown_anime + preview.imported.unknown_episodes;
      toast(
        `${preview.imported.anime} animes y ${preview.imported.watched} capítulos vistos importados.` +
          (skipped
            ? ` ${skipped} registros no estaban en el catálogo y se omitieron.`
            : '')
      );
    } else if (action === 'account_save_codes') {
      if (recoveryDisplay?.user !== user)
        throw new Error('Genera los códigos de nuevo para mostrarlos.');
      saveAccountFile(
        'SeasonAV1 — Códigos de recuperación\nCada código se usa una sola vez.\n\n' +
          recoveryDisplay.codes.join('\n') +
          '\n',
        'SeasonAV1-codigos-recuperacion.txt',
        'text/plain'
      );
    } else if (action === 'account_delete') {
      modal(
        `<div class="auth-form"><p class="eyebrow">ELIMINAR CUENTA</p><h2>Esta acción es permanente.</h2><p>Se borrarán la biblioteca, los capítulos vistos, las preferencias, el historial y el registro de descargas de esta cuenta en la web.</p><form id="account-delete-form">${securityField('delete', 'current_password', 'Contraseña actual')}<div class="field"><label for="delete-confirmation">Escribe ELIMINAR para confirmar</label><input class="form-input" id="delete-confirmation" name="confirmation" autocomplete="off" pattern="ELIMINAR" required></div><p class="form-error" aria-live="polite"></p><button class="button danger" type="submit">Eliminar cuenta permanentemente</button></form>${button('close', 'Conservar mi cuenta', '', '', 'ghost')}</div>`
      );
    }
  } catch (error) {
    toast(error.message, true);
  } finally {
    control.disabled = false;
  }
});

document.addEventListener('submit', async (event) => {
  const form = event.target;
  const actions = {
    'account-password-form': 'account_password',
    'account-codes-form': 'account_recovery_codes',
    'account-recover-form': 'account_recover',
    'account-delete-form': 'account_delete',
  };
  if (!actions[form.id]) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  const submit = form.querySelector('[type="submit"]'),
    user = state.user?.id || 0;
  const interaction = dialogTicket();
  submit.disabled = true;
  try {
    const result = await api(
      actions[form.id],
      Object.fromEntries(new FormData(form))
    );
    if (form.id === 'account-recover-form') {
      if (dialogCurrent(interaction, true)) showAuth('login');
      render();
      toast(result.message);
      return;
    }
    if (form.id === 'account-delete-form') {
      $('#dialog').close();
      accountStateChanged();
      navigate('discover');
      toast(result.message);
      return;
    }
    if (state.user?.id !== user) return;
    form.reset();
    if (result.account) accountInfo = result.account;
    render();
    if (result.recovery_codes && dialogCurrent(interaction, true)) showRecoveryCodes(result.recovery_codes);
    else if (result.recovery_codes) toast('Códigos generados. Si cerraste el formulario sin guardarlos, puedes renovarlos en Mi cuenta.');
    else toast(result.message);
  } catch (error) {
    if (form.isConnected)
      form.querySelector('.form-error').textContent = error.message;
    else toast(error.message, true);
  } finally {
    submit.disabled = false;
  }
});

document.addEventListener('change', async (event) => {
  if (event.target.id !== 'library-file') return;
  const file = event.target.files[0];
  if (!file) return;
  const interaction = dialogTicket();
  try {
    if (file.size > LIBRARY_FILE_LIMIT)
      throw new Error('La biblioteca puede ocupar como máximo 128 MB; se envía por partes.');
    const library = JSON.parse(await file.text());
    if (
      !library ||
      library.format !== 'seasonav1.library/v1' ||
      !Array.isArray(library.entries) ||
      !Array.isArray(library.watched)
    )
      throw new Error('El archivo no es una biblioteca de SeasonAV1.');
    if (!dialogCurrent(interaction)) return;
    const parts = libraryImportChunks(library);
    libraryImportPreview = { parts, name: file.name, next: 0,
      id: crypto.randomUUID().replaceAll('-', ''), imported: { anime:0, watched:0, unknown_anime:0, unknown_episodes:0 } };
    modal(
      `<p class="eyebrow">IMPORTAR BIBLIOTECA</p><h2>Combinar con tu colección.</h2><p>${e(file.name)} · ${library.entries.length} animes · ${library.watched.length} capítulos vistos.</p><p>Los animes coincidentes reciben los estados, notas y puntuaciones del archivo. Los demás animes y los capítulos vistos actuales se conservan. Si se interrumpe, puedes volver a importar la misma copia.</p><p data-library-import-progress role="status"></p><div class="toolbar">${button('account_import_confirm', 'Importar biblioteca', 'upload', '', 'primary')}${button('close', 'Cancelar', '', '', 'ghost')}</div>`
    );
  } catch (error) {
    toast(error.message, true);
  } finally {
    event.target.value = '';
  }
});
document.querySelector('#dialog').addEventListener('close', () => {
  if (recoveryDisplay) document.querySelector('#dialog-body').innerHTML = '';
  recoveryDisplay = null;
  libraryImportPreview = null;
});
