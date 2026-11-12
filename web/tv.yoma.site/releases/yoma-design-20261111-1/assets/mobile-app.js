'use strict';
// Mobile presentation shares the existing actions, data and account protections.
function yomaNative(){return document.documentElement.classList.contains('yoma-native');}
function yomaHomeHero(featured,showHero=true){
  const mode=catalogFilters.category==='Película'?'movies':catalogFilters.airing==='currently_airing'?'airing':'all';
  const a=featured[0]||catalogState?.items?.[0];
  return `<nav class="yoma-home-tabs" aria-label="Descubrir">${[['all','Para ti'],['airing','En emisión'],['movies','Películas']].map(([key,label])=>`<button class="${mode===key?'selected':''}" data-yoma-home="${key}" aria-pressed="${mode===key}">${label}</button>`).join('')}<a class="icon-button" href="#catalog-results" aria-label="Buscar anime">${icon('search')}</a></nav>${a&&showHero?`<section class="yoma-featured"><img src="${e(a.cover)}" alt="" decoding="async"><div class="yoma-featured-shade"></div><span class="yoma-featured-label">DESTACADO DE LA SEMANA</span><div class="yoma-featured-copy"><h1>${e(a.title)}</h1><p>${e(a.category||'Anime')}${a.latest?' · '+e(a.latest)+' episodios disponibles':''}</p><div class="toolbar"><button class="button primary" data-open="${e(a.slug)}">${icon('play')}Ver ahora</button><button class="button ghost" data-action="${a.status==='none'?'follow':'unfollow'}" data-slug="${e(a.slug)}">${icon(a.status==='none'?'plus':'check')}${a.status==='none'?'Mi lista':'En mi lista'}</button></div></div></section>`:''}`;
}
function yomaTodaySection(){
  const today=(new Date().getDay()+6)%7+1,rows=state.anime.filter(a=>a.active&&a.weekday===today);
  return `<section class="personal-section yoma-today"><div class="section-heading"><h2>Estrenos de hoy <span class="yoma-count">${rows.length}</span></h2><button class="text-button" data-view="schedule">Ver todos →</button></div>${rows.length?`<div class="yoma-horizontal">${rows.slice(0,12).map(a=>card(a)).join('')}</div>`:'<p class="muted">Hoy no hay títulos anunciados en el horario actual.</p>'}</section>`;
}
let yomaSeasonMode='all',yomaSeason='',yomaSeasonRows=null,yomaSeasonKey='',yomaSeasonBusy=false,yomaSeasonError='',yomaSeasonSequence=0,yomaSeasonDayReady=false,yomaSeasonSearch=false;
const YOMA_SEASONS=['invierno','primavera','verano','otoño'];
function yomaSeasonName(value){const m=/^(invierno|primavera|verano|otoño)([0-9]{4})$/.exec(value);return m?m[1][0].toUpperCase()+m[1].slice(1)+' '+m[2]:value;}
function yomaSeasonQuery(){return {season:yomaSeason||state.season,airing:yomaSeasonMode==='upcoming'?'not_yet_aired':yomaSeasonMode==='airing'?'currently_airing':'',search,page:1};}
async function yomaLoadSeason(){
  const filters=yomaSeasonQuery(),key=JSON.stringify(filters);if(yomaSeasonBusy&&key===yomaSeasonKey)return;
  if(key!==yomaSeasonKey)yomaSeasonRows=null;
  const seq=++yomaSeasonSequence,user=state.user?.id||0;yomaSeasonBusy=true;yomaSeasonKey=key;yomaSeasonError='';
  try{const result=await api('catalog',filters,true);if(seq!==yomaSeasonSequence||user!==(state.user?.id||0))return;yomaSeasonRows=result.catalog;}
  catch(error){if(seq===yomaSeasonSequence)yomaSeasonError=error.message;}
  finally{if(seq===yomaSeasonSequence){yomaSeasonBusy=false;if(view==='schedule')render();}}
}
function yomaScheduleView(){
  if(!yomaSeason)yomaSeason=state.season;
  if(!yomaSeasonDayReady){yomaSeasonDayReady=true;if(!day)day=(new Date().getDay()+6)%7+1;}
  const live=yomaSeason===state.season&&yomaSeasonMode!=='upcoming';
  let rows;
  if(live)rows=state.anime.filter(a=>a.active&&(!day||a.weekday===day)&&a.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())&&(yomaSeasonMode!=='airing'||a.airing_status==='currently_airing'));
  else {
    const key=JSON.stringify(yomaSeasonQuery());if(key!==yomaSeasonKey&&!yomaSeasonBusy)queueMicrotask(yomaLoadSeason);
    rows=key===yomaSeasonKey?(yomaSeasonRows?.items||[]):[];
  }
  const heading=live?(day===((new Date().getDay()+6)%7+1)?'Estrenos de hoy':day?'Estrenos del '+DAYS[day-1].toLocaleLowerCase():'Estrenos de la semana'):yomaSeasonMode==='upcoming'?'Próximos estrenos':'Animes de la temporada';
  return `<section class="yoma-season"><header><h1>Temporada</h1><p>Descubre lo que se estrena</p></header><div class="yoma-season-pill"><button class="icon-button" data-yoma-season-shift="-1" aria-label="Temporada anterior"><span aria-hidden="true">‹</span></button><strong>${e(yomaSeasonName(yomaSeason))}</strong><button class="icon-button" data-yoma-season-shift="1" aria-label="Temporada siguiente"><span aria-hidden="true">›</span></button></div><nav class="yoma-season-modes" aria-label="Estado de emisión">${[['all','Todos'],['airing','En emisión'],['upcoming','Próximos']].map(([key,label])=>`<button data-yoma-season-mode="${key}" class="${yomaSeasonMode===key?'selected':''}" aria-pressed="${yomaSeasonMode===key}">${label}</button>`).join('')}</nav>${live?`<div class="day-tabs" role="group" aria-label="Día del horario">${[1,2,3,4,5,6,7].map(d=>`<button class="day-tab ${day===d?'active':''}" data-day="${d===day?0:d}" aria-pressed="${day===d}">${['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'][d-1]}</button>`).join('')}</div>`:''}<div class="section-heading"><h2>${e(heading)}</h2><span>${live?rows.length:yomaSeasonRows?.total||rows.length} títulos</span><button class="icon-button" data-yoma-season-search aria-label="Buscar en la temporada" aria-expanded="${yomaSeasonSearch}">${icon('search')}</button></div>${yomaSeasonSearch||search?searchBox():''}<div class="yoma-season-grid">${rows.map(a=>`<article class="yoma-release"><a data-open="${e(a.slug)}" href="#anime-${e(a.slug)}"><div class="yoma-release-cover"><img src="${e(a.cover)}" loading="lazy" alt=""><span>${a.latest?'Ep. '+e(a.latest):e(a.category||'Anime')}</span></div><h3>${e(a.title)}</h3></a><p>${live?e(DAYS[a.weekday-1])+(a.latest?' · Episodio '+e(a.latest):''):a.start_date?e(a.start_date):'Fecha por anunciar'}</p></article>`).join('')||`<p class="muted">${yomaSeasonBusy?'Consultando el catálogo…':e(yomaSeasonError||'No hay títulos para esta selección.')}</p>`}</div><div class="yoma-season-footer"><button class="text-button" data-action="calendar_open">Ver calendario completo →</button><a class="text-button" href="calendar.php">Exportar .ics</a></div>${!live?'<p class="muted yoma-schedule-note">Este catálogo muestra las fechas conocidas; el horario semanal corresponde a la temporada actual.</p>':''}</section>`;
}
document.addEventListener('click',event=>{
  const mode=event.target.closest('[data-yoma-season-mode]'),shift=event.target.closest('[data-yoma-season-shift]'),find=event.target.closest('[data-yoma-season-search]');
  if(!mode&&!shift&&!find)return;event.preventDefault();
  if(mode)yomaSeasonMode=mode.dataset.yomaSeasonMode;
  if(shift){const m=/^(invierno|primavera|verano|otoño)([0-9]{4})$/.exec(yomaSeason||state.season);if(m){const offset=Number(m[2])*4+YOMA_SEASONS.indexOf(m[1])+Number(shift.dataset.yomaSeasonShift);const year=Math.floor(offset/4);if(year>=1900&&year<=2100)yomaSeason=YOMA_SEASONS[((offset%4)+4)%4]+year;}}
  if(find)yomaSeasonSearch=!yomaSeasonSearch;
  if(!find){yomaSeasonRows=null;yomaSeasonKey='';yomaSeasonSequence++;yomaSeasonBusy=false;}
  render();if(find&&yomaSeasonSearch)document.querySelector('#search')?.focus();
});
document.addEventListener('click',event=>{
  const node=event.target.closest('[data-yoma-home]');if(!node)return;
  const mode=node.dataset.yomaHome;
  Object.assign(catalogFilters,{...CATALOG_DEFAULTS,include_genres:[],exclude_genres:[],category:mode==='movies'?'Película':'',airing:mode==='airing'?'currently_airing':''});
  catalogWriteRoute();render();loadCatalog();
  if(mode!=='all')document.querySelector('#catalog-filters')?.scrollIntoView({behavior:'smooth',block:'start'});
});

document.addEventListener('season-account-reset',()=>{yomaSeasonRows=null;yomaSeasonKey='';yomaSeasonBusy=false;yomaSeasonError='';yomaSeasonSequence++;});
