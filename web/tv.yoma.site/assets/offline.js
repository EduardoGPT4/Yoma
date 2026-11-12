'use strict';
const escapeHTML = (v) =>
  String(v || '').replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ]
  );
const normalize = (v) =>
  v
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();
let publicCatalog = [],
  catalogDate = 0,
  page = 1;
function renderOffline() {
  const term = normalize(document.querySelector('#offline-search').value),
    rows = publicCatalog.filter((a) => normalize(a.title).includes(term)),
    pages = Math.max(1, Math.ceil(rows.length / 24));
  page = Math.max(1, Math.min(pages, page));
  document.querySelector('#offline-count').textContent =
    `${rows.length} animes disponibles en el catálogo guardado${catalogDate?' · Índice: '+new Date(catalogDate*1000).toLocaleString('es-MX'):''}`;
  document.querySelector('#offline-page').textContent = `${page} / ${pages}`;
  document.querySelector('#offline-prev').disabled = page <= 1;
  document.querySelector('#offline-next').disabled = page >= pages;
  document.querySelector('#offline-results').innerHTML =
    `<div class="card-grid">${rows
      .slice((page - 1) * 24, page * 24)
      .map(
        (a) =>
          `<article class="anime-card"><div class="offline-cover"><span>${escapeHTML(a.title.slice(0, 1))}</span></div><h3>${escapeHTML(a.title)}</h3><p class="muted">${escapeHTML(a.category)}</p><a class="button small ghost" href="./#anime-${encodeURIComponent(a.slug)}">Abrir cuando haya conexión</a></article>`
      )
      .join('')}</div>`;
}
document.querySelector('#offline-search').addEventListener('input', () => {
  page = 1;
  renderOffline();
});
document.querySelector('#offline-prev').addEventListener('click', () => {
  page--;
  renderOffline();
});
document.querySelector('#offline-next').addEventListener('click', () => {
  page++;
  renderOffline();
});
async function refreshOfflineCatalog() {
  for(const source of ['catalog-public.php','data/offline-catalog.json']) {
    try {
      const response=await fetch(source,{cache:'no-cache'});
      if(!response.ok) throw new Error('No disponible');
      const data=await response.json();
      if(!Array.isArray(data.items)||!data.items.every(a=>typeof a.title==='string'&&typeof a.slug==='string')) throw new Error('Índice inválido');
      publicCatalog=data.items;catalogDate=Number(data.updated_at||data.fetched_at)||0;renderOffline();return;
    } catch {}
  }
  if(!publicCatalog.length) document.querySelector('#offline-count').textContent='El catálogo todavía no se guardó. Abre la web con conexión una vez para prepararlo.';
}
window.addEventListener('online',refreshOfflineCatalog);
refreshOfflineCatalog();
