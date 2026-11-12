'use strict';
const statePatchClocks = new WeakMap();
let sessionRefresh = null;

function mergeStatePatch(current, patch) {
  if (!current || Number(current.user?.id || 0) !== Number(patch.user_id))
    return current;
  const clocks = statePatchClocks.get(current) || {
    base: Number(current.revision || 0),
    anime: new Map(),
    jobs: new Map(),
    queue_summary: new Map(),
    history: new Map(),
    fields: new Map(),
  };
  const revision = Number(patch.revision || 0);
  clocks.queue_summary ||= new Map();
  const next = { ...current };
  function mergeRows(name, key, rows, replace = false, removed = []) {
    const timestamps = clocks[name];
    const values = new Map(
      (replace ? [] : current[name] || []).map((row) => [String(row[key]), row])
    );
    if (replace)
      for (const row of current[name] || []) {
        const id = String(row[key]);
        if ((timestamps.get(id) || clocks.base) > revision) values.set(id, row);
      }
    for (const row of rows || []) {
      const id = String(row[key]);
      if ((timestamps.get(id) || clocks.base) > revision) continue;
      const existing = values.get(id);
      if (
        name === 'jobs' &&
        existing?.status === 'confirmed' &&
        row.status !== 'confirmed' && !(patch.reset_jobs||[]).includes(Number(row.id))
      )
        continue;
      values.set(id, row);
      timestamps.set(id, revision);
    }
    for (const id of removed) {
      if ((timestamps.get(String(id)) || clocks.base) > revision) continue;
      values.delete(String(id));
      timestamps.set(String(id), revision);
    }
    next[name] = [...values.values()];
  }
  mergeRows(
    'anime',
    'slug',
    patch.anime,
    Boolean(patch.replace_anime),
    patch.removed_anime
  );
  mergeRows('jobs', 'id', patch.jobs);
  if (patch.queue_summary) mergeRows('queue_summary', 'slug', patch.queue_summary);
  mergeRows('history', 'id', patch.history);
  next.anime.sort(
    (a, b) =>
      Number(b.active) - Number(a.active) ||
      a.weekday - b.weekday ||
      a.title.localeCompare(b.title)
  );
  next.jobs.sort(
    (a, b) =>
      Number(b.added_at) - Number(a.added_at) || Number(b.id) - Number(a.id)
  );
  next.history.sort((a, b) => Number(b.id) - Number(a.id));
  next.history = next.history.slice(0, 80);
  for (const key of ['csrf', 'settings', 'preferences_saved', 'updated_at', 'queue_totals']) {
    if (
      !Object.hasOwn(patch, key) ||
      (clocks.fields.get(key) || clocks.base) > revision
    )
      continue;
    next[key] = patch[key];
    clocks.fields.set(key, revision);
  }
  statePatchClocks.set(next, clocks);
  return next;
}

function acceptedPersonalUpdates(current, patch) {
  const clocks = statePatchClocks.get(current);
  if (!clocks) return [];
  const revision = Number(patch.revision || 0),
    bySlug = new Map(current.anime.map((anime) => [anime.slug, anime]));
  return [...(patch.anime || []), ...(patch.personal_updates || [])]
    .filter((anime) => clocks.anime.get(String(anime.slug)) === revision)
    .map((anime) => bySlug.get(anime.slug) || anime);
}
async function api(
  action,
  data = {},
  get = false,
  { assignDetail = true } = {}
) {
  const requestDialog = typeof detailSequence === 'undefined' ? null : detailSequence;
  const requestUser = state?.user?.id || 0;
  const csrf = state?.csrf ?? $('meta[name="csrf-token"]').content;
  const url = get
    ? `actions.php?${new URLSearchParams({ action, ...data })}`
    : ['library_import', 'mal_xml'].includes(action)
      ? 'actions.php?transfer=library'
      : 'actions.php';
  const response = await fetch(url, {
    method: get ? 'GET' : 'POST',
    credentials: 'same-origin',
    keepalive: ['watch_scrobble','player_save'].includes(action),
    headers: get
      ? {}
      : {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrf,
          'X-Season-Response': 'patch',
        },
    body: get ? undefined : JSON.stringify({ action, ...data }),
  });
  const result = await response.json().catch(() => ({
    ok: false,
    message:
      'La página no respondió correctamente. Recarga e intenta de nuevo.',
  }));
  if (!response.ok || !result.ok) {
    if (response.status === 401 && state?.user && action !== 'login') {
      if (!sessionRefresh)
        sessionRefresh = fetch('actions.php?action=state', {
          credentials: 'same-origin',
        })
          .then((r) => r.json())
          .then((fresh) => {
            if (fresh.ok && fresh.data) {
              accountStateChanged();
              state = fresh.data;
              syncCatalogPersonal();
              $('#dialog').close();
              render();
            }
          })
          .catch(() => {})
          .finally(() => (sessionRefresh = null));
      await sessionRefresh;
    }
    throw new Error(result.message || 'No se pudo completar la operación.');
  }
  if (result.data) {
    if ((state?.user?.id || 0) !== (result.data.user?.id || 0))
      accountStateChanged();
    state = result.data;
    syncCatalogPersonal();
  } else if (result.patch) {
    const previous = state;
    state = mergeStatePatch(state, result.patch);
    if (state !== previous)
      syncCatalogPersonal(acceptedPersonalUpdates(state, result.patch));
  }
  if (assignDetail && result.detail && action !== 'detail' &&
    requestUser === (state?.user?.id || 0) &&
    (requestDialog === null || requestDialog === detailSequence))
    detailState = result.detail;
  if (typeof acceptFeatureResult === 'function') acceptFeatureResult(result);
  if (typeof acceptExperienceResult === 'function') acceptExperienceResult(result,requestUser);
  if ((result.patch || result.data) && typeof catalogPersonalChanged === 'function')
    catalogPersonalChanged();
  if (
    typeof loadFeatureHome === 'function' &&
    ['follow', 'unfollow', 'watched', 'mal_disconnect'].includes(action)
  ) {
    statsPage = null;
    queueMicrotask(() => loadFeatureHome(false).catch(() => {}));
  }
  if (
    result.data &&
    typeof loadFeatureHome === 'function' &&
    (!featureHome ||
      Number(featureHome.user_id) !== Number(state.user?.id || 0))
  )
    queueMicrotask(() => loadFeatureHome().catch(() => {}));
  return result;
}
