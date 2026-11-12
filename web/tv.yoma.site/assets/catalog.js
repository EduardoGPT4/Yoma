'use strict';
const CATALOG_DEFAULTS = {
  search:'', category:'', scope:'all', order:'recent', year:'', airing:'',
  season:'', letter:'', library:'', download:'', language:'', unwatched:'',
  include_genres:[], exclude_genres:[], genre_mode:'all', page:1,
};
const CATALOG_ORDERS = {
  recent:'Recién añadidos', title:'Nombre · A–Z', title_desc:'Nombre · Z–A',
  score:'Mi puntuación', episodes:'Más capítulos disponibles', premiere:'Estreno más reciente', updated:'Última actualización',
};
const CATALOG_LIBRARY = {
  '':'Cualquier estado', followed:'En mi biblioteca', watching:'Viendo', planned:'Planeado',
  completed:'Completado', paused:'Pausado', dropped:'Abandonado', favorites:'Favoritos', none:'No está en mi biblioteca',
};
const CATALOG_DOWNLOADS = {'':'Cualquier descarga', downloaded:'Con capítulos descargados', queued:'En cola', unprepared:'Sin preparar'};
const CATALOG_AIRING = {'':'Cualquier emisión',currently_airing:'En emisión',finished_airing:'Finalizado',not_yet_aired:'Sin estrenar',unknown:'Estado sin datos'};
let catalogState = null, catalogBusy = false, catalogError = '', catalogSequence = 0, catalogTimer, catalogMore = false;
const catalogFilters = catalogReadRoute();
function catalogReadRoute(hash = location.hash) {
  const f = {...CATALOG_DEFAULTS,include_genres:[],exclude_genres:[]};
  if (!hash.startsWith('#discover?')) return f;
  const params = new URLSearchParams(hash.slice(hash.indexOf('?')+1));
  for (const key of Object.keys(f)) {
    if (key.endsWith('_genres')) {
      try { const values=JSON.parse(params.get(key)||'[]'); if(Array.isArray(values)) f[key]=[...new Set(values.filter(v=>typeof v==='string' && v.length<=80 && v.trim()))].slice(0,20); } catch {}
    } else if (params.has(key)) f[key] = params.get(key).slice(0,key==='search'?120:80);
  }
  f.page = Math.max(1,Math.min(100000,Number.parseInt(f.page,10)||1));
  f.scope = f.scope==='season'?'season':'all';
  f.genre_mode = f.genre_mode==='any'?'any':'all';
  f.order = Object.hasOwn(CATALOG_ORDERS,f.order)?f.order:'recent';
  f.library = Object.hasOwn(CATALOG_LIBRARY,f.library)?f.library:'';
  f.download = Object.hasOwn(CATALOG_DOWNLOADS,f.download)?f.download:'';
  f.airing = Object.hasOwn(CATALOG_AIRING,f.airing)?f.airing:'';
  f.letter = /^[A-Z#]$/.test(f.letter)?f.letter:'';
  f.unwatched = f.unwatched==='1'?'1':'';
  f.language = ['','SUB','LAT','DUB','unknown'].includes(f.language)?f.language:'';
  f.year = /^(?:19|20|21)\d{2}$/.test(f.year)||f.year==='unknown'?f.year:'';
  f.season = /^(invierno|primavera|verano|otoño)(?:19|20|21)\d{2}$/.test(f.season)||f.season==='unknown'?f.season:'';
  return f;
}
function catalogRoute() {
  const p = new URLSearchParams();
  for (const [key,value] of Object.entries(catalogFilters)) {
    if (Array.isArray(value)) { if(value.length) p.set(key,JSON.stringify(value)); }
    else if (String(value)!==String(CATALOG_DEFAULTS[key])) p.set(key,String(value));
  }
  return '#discover'+(p.size?'?'+p:'');
}
function catalogWriteRoute(replace=false) {
  if (view!=='discover') return;
  const hash = catalogRoute();
  if (location.hash!==hash) history[replace?'replaceState':'pushState'](null,'',location.pathname+location.search+hash);
}
function catalogRestoreRoute() {
  if (location.hash.split('?')[0]!=='#discover') return;
  const next = catalogReadRoute();
  if (JSON.stringify(next)===JSON.stringify(catalogFilters) && view==='discover') return;
  clearTimeout(catalogTimer);
  Object.assign(catalogFilters,next);
  view='discover';
  if (state) { render(); loadCatalog(); }
}
function catalogSelect(key,label,options,{personal=false}={}) {
  const choices = Array.isArray(options)?options:Object.entries(options);
  return `<label class="catalog-field"><span>${e(label)}</span><select id="catalog-${key}" class="select-input" aria-label="${e(label)}" ${personal&&!state.user?'disabled':''}>${choices.map(([v,t])=>`<option value="${e(v)}" ${String(catalogFilters[key])===String(v)?'selected':''}>${e(t)}</option>`).join('')}</select></label>`;
}
function catalogAdvanced() {
  const f=catalogFilters, c=catalogState;
  const addGenre = (key,label) => `<label class="catalog-field"><span>${e(label)}</span><select id="catalog-${key}" class="select-input" aria-label="${e(label)}"><option value="">Añadir género…</option>${(c?.genres||[]).filter(g=>!f.include_genres.includes(g)&&!f.exclude_genres.includes(g)).map(g=>`<option value="${e(g)}">${e(g)}</option>`).join('')}</select></label>`;
  return `<section id="catalog-advanced" class="catalog-advanced" aria-label="Más filtros del catálogo" ${catalogMore?'':'hidden'}>
    <div class="catalog-advanced-grid">
      ${catalogSelect('library','Mi biblioteca',CATALOG_LIBRARY,{personal:true})}
      ${catalogSelect('download','Descargas',CATALOG_DOWNLOADS,{personal:true})}
      ${catalogSelect('scope','Horario',[['all','Todo el catálogo'],['season','En el horario actual']])}
      ${catalogSelect('year','Año de estreno',[['','Todos los años'],...(c?.years||[]).map(y=>[y,y]),['unknown','Año sin datos']])}
      ${catalogSelect('season','Temporada de estreno',[['','Todas las temporadas'],...(c?.seasons||[]).map(s=>[s,s]),['unknown','Temporada sin datos']])}
      ${catalogSelect('airing','Estado de emisión',CATALOG_AIRING)}
      ${catalogSelect('language','Idioma comprobado',[['','Cualquier idioma'],['SUB','SUB · Subtitulado'],['LAT','LAT · Latino'],['DUB','DUB · Doblado'],['unknown','Idioma sin comprobar']])}
      <label class="unwatched-filter"><input id="catalog-unwatched" type="checkbox" ${f.unwatched?'checked':''} ${!state.user?'disabled':''}> Con capítulos sin ver</label>
    </div>
    ${!state.user?'<p class="catalog-filter-help">Inicia sesión para usar biblioteca, descargas, capítulos sin ver y tu puntuación. <button class="text-button" data-action="account">Iniciar sesión</button></p>':''}
    <div class="catalog-alphabet" role="group" aria-label="Letra inicial"><span>Índice</span>${['','\u0023',...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'].map(l=>`<button class="catalog-letter ${f.letter===l?'selected':''}" data-action="catalog_letter" data-value="${e(l)}" aria-label="${l?'Letra '+l:'Todas las letras'}" aria-pressed="${f.letter===l}">${l||'Todo'}</button>`).join('')}</div>
    <div class="catalog-genre-controls">${catalogSelect('genre_mode','Coincidencia de géneros',[['all','Todos los incluidos'],['any','Cualquiera de los incluidos']])}${addGenre('include_genres','Incluir géneros')}${addGenre('exclude_genres','Excluir estos géneros')}<p class="catalog-filter-help">Busca en todo AnimeAV1. Elige si deben coincidir todos o cualquiera de los géneros incluidos; los excluidos siempre se descartan. «Mi biblioteca» limita los resultados solo si lo eliges.</p></div>
    <details class="catalog-data-help"><summary>Sobre los datos del catálogo</summary><p>Géneros, años y emisión proceden del índice público de AnimeAV1, independiente de tu lista MAL.${c?` Fichas consultadas: ${c.coverage?.source??0} / ${c.all_total}.`:''} Las temporadas requieren una fecha de estreno completa y el idioma se confirma al consultar servidores de capítulos. Los datos sin confirmar no se inventan.</p>${typeof catalogCoverageView==='function'?catalogCoverageView(c):''}<a class="text-button" href="https://animeav1.com/catalogo" target="_blank" rel="noopener noreferrer">Consultar catálogo de AnimeAV1 ↗</a></details>
  </section>`;
}
function catalogChips() {
  const f=catalogFilters, chips=[];
  const add=(key,label,value='')=>chips.push(`<button class="filter-chip" data-action="catalog_remove" data-key="${key}" data-value="${e(value)}" aria-label="Quitar filtro ${e(label)}" title="Quitar filtro">${e(label)}${icon('close')}</button>`);
  if(f.search) add('search','Búsqueda: '+f.search);
  if(f.genre_mode==='any'&&f.include_genres.length) add('genre_mode','Géneros: cualquiera');
  if(f.category) add('category',f.category);
  if(f.order!=='recent') add('order',CATALOG_ORDERS[f.order]);
  if(f.scope==='season') add('scope','Horario actual');
  if(f.library) add('library',CATALOG_LIBRARY[f.library]);
  if(f.download) add('download',CATALOG_DOWNLOADS[f.download]);
  if(f.year) add('year',f.year==='unknown'?'Año sin datos':'Año: '+f.year);
  if(f.season) add('season',f.season==='unknown'?'Temporada sin datos':f.season);
  if(f.airing) add('airing',CATALOG_AIRING[f.airing]);
  if(f.letter) add('letter','Letra: '+f.letter);
  if(f.language) add('language',f.language==='unknown'?'Idioma sin comprobar':'Idioma: '+f.language);
  if(f.unwatched) add('unwatched','Con capítulos sin ver');
  f.include_genres.forEach(g=>add('include_genres','Género: '+g,g));
  f.exclude_genres.forEach(g=>add('exclude_genres','Sin: '+g,g));
  return chips.length?`<div class="catalog-chips" aria-label="Filtros activos">${chips.join('')}${button('catalog_clear','Limpiar filtros','','','small ghost')}</div>`:'';
}
function catalogView() {
  const featured=state.anime.filter(a=>a.active).slice(0,3), total=catalogState?.all_total??'…';
  const advanced=Object.keys(catalogFilters).filter(k=>!['page','search','category','order'].includes(k)).reduce((n,k)=>n+(Array.isArray(catalogFilters[k])?catalogFilters[k].length:Number(catalogFilters[k]!==CATALOG_DEFAULTS[k])),0);
  const filtered=Boolean(advanced || catalogFilters.search || catalogFilters.category || catalogFilters.order!=='recent' || catalogFilters.page>1);
  return `<section class="hero catalog-hero"><div class="hero-copy"><p class="eyebrow"><span class="online-dot"></span> TODAS TUS HISTORIAS, EN UN LUGAR</p><h1>Tus historias.<br><span>A tu ritmo.</span></h1><p>Sigue tu lista, mira capítulos o llévalos a tu PC.</p><div class="hero-buttons">${button('connect','Conectar AnimeAV1 Plus','pc','','primary')}${exeDownload()}${button('view_radio','Escuchar radio','music','','ghost')}</div></div><div class="hero-posters">${featured.map(a=>`<a href="#anime-${e(a.slug)}" data-open="${e(a.slug)}" class="hero-poster" aria-label="Ver ${e(a.title)}"><img src="${e(a.cover)}" alt="${e(a.title)}" decoding="async"></a>`).join('')}<span class="floating-label">${icon('library')}${e(total)} títulos para explorar</span></div></section>${!filtered && typeof catalogPersonalSections==='function'?catalogPersonalSections():''}
    <div class="catalog-intro"><div><p class="eyebrow">CATÁLOGO COMPLETO</p><h2>Tu próxima historia está aquí.</h2><p>Abre una ficha para elegir capítulos o preparar el anime completo.</p></div>${state.user?.is_admin?button('catalog_sync','Buscar novedades','refresh','','small ghost'):''}</div>
    <section class="catalog-filter-panel" aria-label="Filtros del catálogo">
      <div class="catalog-quick-filters"><label class="search-box">${icon('search')}<input id="catalog-search" type="search" placeholder="Naruto, One Piece, tu próximo favorito…" aria-label="Buscar en todos los animes" maxlength="120" value="${e(catalogFilters.search)}"></label>${catalogSelect('category','Formato',[['','Todos los formatos'],...(catalogState?.categories||[]).map(c=>[c,c])])}${catalogSelect('order','Ordenar catálogo',Object.entries(CATALOG_ORDERS).filter(([k])=>k!=='score'||state.user||catalogFilters.order==='score'))}<button class="button ghost catalog-more" data-action="catalog_more" aria-controls="catalog-advanced" aria-expanded="${catalogMore}">${icon('settings')}Más filtros${advanced?` <span class="filter-count">${advanced}</span>`:''}</button></div>
      ${catalogAdvanced()}${catalogChips()}${typeof savedFilterView==='function'?savedFilterView():''}
      <div class="catalog-count" role="status"><p>${catalogCount()}</p><span class="muted">${catalogBusy?'Buscando…':catalogState?'Índice: '+e(dateText(catalogState.updated_at)):''}</span></div>
    </section><div id="catalog-results" aria-live="polite" ${catalogBusy?'aria-busy="true"':''}>${catalogResults()}</div>`;
}
function catalogCount() {
  if(catalogError) return 'No se pudo completar la búsqueda';
  const c=catalogState;
  return c?`${c.total.toLocaleString('es-MX')} ${c.total===1?'anime':'animes'}${catalogFilters.search?` para «${e(catalogFilters.search)}»`:''} · Página ${c.page} de ${c.pages}`:'Abriendo el catálogo…';
}
function catalogResults() {
  if(catalogError) return empty('No se pudo cargar el catálogo',catalogError,button('catalog_retry','Reintentar','refresh','','primary')+button('catalog_clear','Limpiar filtros','close','','ghost'));
  if(!catalogState) return '<div class="loading-view"><span class="spinner"></span><p>Abriendo el catálogo…</p></div>';
  const c=catalogState;
  return `${c.items.length?cards(c.items):empty('No encontramos esa historia','Prueba con una parte del título o cambia los filtros.',button('catalog_clear','Limpiar filtros','refresh','','ghost'))}<nav class="catalog-pagination" aria-label="Páginas del catálogo">${button('catalog_previous','Anterior','',catalogBusy||c.page<=1?'disabled':'','ghost')}<label>Ir a página <input id="catalog-page" class="form-input" type="number" aria-label="Número de página" min="1" max="${c.pages}" value="${c.page}"></label>${button('catalog_go','Ir','','','ghost')}<span>de ${c.pages}</span>${button('catalog_next','Siguiente','arrow',catalogBusy||c.page>=c.pages?'disabled':'','primary')}</nav>`;
}
async function loadCatalog() {
  clearTimeout(catalogTimer);
  const sequence=++catalogSequence, filters={...catalogFilters,include_genres:JSON.stringify(catalogFilters.include_genres),exclude_genres:JSON.stringify(catalogFilters.exclude_genres)}, user=state.user?.id??0;
  catalogBusy=true; catalogError='';
  document.querySelector('#catalog-results')?.setAttribute('aria-busy','true');
  try {
    const result=await api('catalog',filters,true);
    if(sequence!==catalogSequence) return;
    if(user!==(state.user?.id??0)) return loadCatalog();
    catalogState=result.catalog; catalogFilters.page=catalogState.page;
    if(catalogState.selected_genres) {
      catalogFilters.include_genres=catalogState.selected_genres.include;
      catalogFilters.exclude_genres=catalogState.selected_genres.exclude;
    }
    catalogWriteRoute(true);
  } catch(error) {if(sequence===catalogSequence) catalogError=error.message;}
  finally {
    if(sequence===catalogSequence) {
      catalogBusy=false;
      if(view==='discover') {
        const input=document.activeElement, id=input?.id, position=input?.selectionStart;
        render();
        const next=id?document.getElementById(id):null;
        if(next) {next.focus({preventScroll:true});if(next.type==='search'&&position!==null) next.setSelectionRange(position,position);}
      }
    }
  }
}
function syncCatalogPersonal(changes = null) {
  const updates = changes ? new Map(changes.map((a) => [a.slug, a])) : null;
  const keys = [
    'status',
    'favorite',
    'excluded',
    'score',
    'notes',
    'watched',
    'downloaded',
    'latest_job',
    'title',
    'synopsis',
    'cover',
    'weekday',
    'latest',
    'active',
    'catalog_complete',
    'start_date',
    'season',
    'category',
    'episodes',
    'mal',
    'watch_progress',
    'next_airing',
    'genres',
    'year',
    'airing_status',
    'metadata_source',
    'mal_mean',
    'studios',
  ];
  const rows = [
    ...(catalogState?.items ?? []),
    ...(detailState ? [detailState.anime] : []),
  ];
  rows.forEach((a) => {
    if (updates && !updates.has(a.slug)) return;
    const personal = updates?.get(a.slug) ??
      state.anime.find((item) => item.slug === a.slug) ?? {
        status: 'none',
        favorite: false,
        excluded: false,
        score: 0,
        notes: '',
        watched: 0,
        downloaded: 0,
        latest_job: null,
        mal: null,
        watch_progress: 0,
      };
    keys.forEach((k) => {
      if (Object.hasOwn(personal, k)) a[k] = personal[k];
    });
  });
}
function lookupAnime(slug) {
  return (
    state.anime.find((a) => a.slug === slug) ||
    catalogState?.items.find((a) => a.slug === slug) ||
    (detailState?.anime.slug === slug ? detailState.anime : null)
  );
}
function catalogPersonalChanged() {
  if (!(catalogFilters.library || catalogFilters.download || catalogFilters.unwatched || catalogFilters.order==='score')) return;
  catalogSequence++;
  clearTimeout(catalogTimer);
  if (view==='discover') catalogTimer=setTimeout(loadCatalog,250);
  else catalogState=null;
}

async function catalogAction(action,b) {
  if(action==='catalog_more') {
    catalogMore=!catalogMore;
    const panel=document.getElementById('catalog-advanced');
    panel.hidden=!catalogMore;
    b.setAttribute('aria-expanded',String(catalogMore));
    return;
  }
  if(action==='catalog_sync') {
    if(!requireUser()) return;
    const result=await api('maintenance');
    toast(result.maintenance_result.reason||'Actualización incremental iniciada. El catálogo se recorre por lotes.');
  } else if(action==='catalog_previous') catalogFilters.page--;
  else if(action==='catalog_next') catalogFilters.page++;
  else if(action==='catalog_go') catalogFilters.page=Math.max(1,Math.min(catalogState.pages,Number(document.querySelector('#catalog-page').value)||1));
  else if(action==='catalog_letter') {catalogFilters.letter=b.dataset.value;catalogFilters.page=1;}
  else if(action==='catalog_remove') {
    const key=b.dataset.key;
    if(!Object.hasOwn(CATALOG_DEFAULTS,key)) return;
    catalogFilters[key]=Array.isArray(catalogFilters[key])?catalogFilters[key].filter(v=>v!==b.dataset.value):CATALOG_DEFAULTS[key];
    catalogFilters.page=1;
  } else if(action==='catalog_clear') Object.assign(catalogFilters,CATALOG_DEFAULTS,{include_genres:[],exclude_genres:[]});
  catalogWriteRoute();
  await loadCatalog();
  if(['catalog_previous','catalog_next','catalog_go'].includes(action)) document.querySelector('.catalog-filter-panel')?.scrollIntoView({behavior:'smooth'});
}
document.addEventListener('input',event=>{
  if(event.target.id==='catalog-search') {
    catalogFilters.search=event.target.value; catalogFilters.page=1;
    // Invalidate an older response immediately, before the debounce has elapsed.
    catalogSequence++;
    clearTimeout(catalogTimer);
    catalogTimer=setTimeout(()=>{catalogWriteRoute();loadCatalog();},350);
  }
});
document.addEventListener('change',event=>{
  const key=event.target.id?.startsWith('catalog-')?event.target.id.slice(8):'';
  if(!Object.hasOwn(CATALOG_DEFAULTS,key)||key==='page'||key==='search') return;
  if(key.endsWith('_genres')) {
    const value=event.target.value;
    if(!value) return;
    if(catalogFilters[key].length>=20) {toast('Puedes elegir hasta 20 géneros por grupo.',true);return;}
    if(!catalogFilters[key].includes(value)) catalogFilters[key]=[...catalogFilters[key],value];
  } else catalogFilters[key]=event.target.type==='checkbox'?(event.target.checked?'1':''):event.target.value;
  catalogFilters.page=1;
  catalogSequence++;
  catalogWriteRoute(); loadCatalog();
});
document.addEventListener('keydown',event=>{
  if(event.target.id==='catalog-page'&&event.key==='Enter') {event.preventDefault();catalogAction('catalog_go').catch(error=>toast(error.message,true));}
});
window.addEventListener('popstate',catalogRestoreRoute);
window.addEventListener('hashchange',catalogRestoreRoute);
