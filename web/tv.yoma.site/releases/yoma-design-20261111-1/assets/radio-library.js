'use strict';
(() => {
  const proto=AnimeRadio.prototype,original=proto.playlist,pause=proto.pause,off=proto.off,start=proto.start,next=proto.next;
  proto.setLibraryScope=function(user){
    const scope=String(user||0);if(this.libraryScope===scope)return;
    if(this.libraryScope!==undefined)this.off();this.libraryScope=scope;this.collection='all';this.cloudConflict=null;this.cloudRevision='';this.library={favorites:[],lists:[]};
    try{const saved=JSON.parse(localStorage.getItem(`seasonav1.radio.library.${scope}`)||'{}');
      const valid=ids=>Array.isArray(ids)?[...new Set(ids.filter(id=>typeof id==='string'&&/^[\w-]{11}$/.test(id)))].slice(0,300):[];
      this.library={favorites:valid(saved.favorites),lists:(Array.isArray(saved.lists)?saved.lists:[]).filter(l=>typeof l?.id==='string'&&/^[a-f0-9]{16}$/.test(l.id)&&typeof l.name==='string').slice(0,20).map(l=>({id:l.id,name:l.name.slice(0,60),ids:valid(l.ids)}))};
    }catch{}
    if(Number(scope))queueMicrotask(()=>loadPersonalUI().catch(()=>{}));
  };
  proto.storeLibrary=function(){if(Number(this.libraryScope)){try{localStorage.setItem(`seasonav1.radio.library.${this.libraryScope}.dirty`,'yes');}catch{}if(typeof syncRadioLibrary==='function')syncRadioLibrary();}try{localStorage.setItem(`seasonav1.radio.library.${this.libraryScope}`,JSON.stringify(this.library));}catch{toast('No se pudieron guardar tus listas en este navegador.',true);}};
  proto.playlist=function(){const list=original.call(this);if(!this.library||this.collection==='all')return list;const ids=this.collection==='favorites'?this.library.favorites:this.library.lists.find(l=>l.id===this.collection)?.ids||[];return list.filter(({t})=>ids.includes(t.id));};
  proto.start=function(id){if(!this.playlist().length){this.status('Esta selección no contiene canciones.');return;}return start.call(this,id);};
  proto.pause=function(message){clearTimeout(this.skipTimer);return pause.call(this,message);};
  proto.next=function(direction=1,automatic=false){if(!automatic){clearTimeout(this.skipTimer);this.errorStreak=0;}return next.call(this,direction,automatic);};
  proto.off=function(){clearTimeout(this.skipTimer);this.errorStreak=0;return off.call(this);};
  proto.unavailable=function(){
    clearTimeout(this.skipTimer);this.errorStreak=(this.errorStreak||0)+1;
    const candidates=this.playlist().filter(({t})=>!this.skipped.has(t.id));
    if(this.errorStreak>=3||!candidates.length){this.pause('Radio en pausa: varios videos no están disponibles. Elige otra canción.');return;}
    this.status('Video no disponible. Se probará la siguiente canción…');const generation=this.generation;
    this.skipTimer=setTimeout(()=>{if(generation!==this.generation||!this.enabled||this.minimized||document.hidden||document.getElementById('dialog').open)return;this.index=candidates[0].i;this.updateTrack();if(this.ready)this.player.loadVideoById(this.current.id);},900);
  };
})();
function radioLibraryControls(){radio.setLibraryScope(state.user?.id);return `<div class="toolbar radio-library-controls"><label>Mi música<select id="radio-collection" class="select-input"><option value="all">Toda la selección</option><option value="favorites" ${radio.collection==='favorites'?'selected':''}>Favoritos</option>${radio.library.lists.map(l=>`<option value="${l.id}" ${radio.collection===l.id?'selected':''}>${e(l.name)}</option>`).join('')}</select></label><button class="button ghost" data-radio-library="manage">Gestionar listas</button>${radio.cloudConflict?'<button class="button small ghost" data-personal="radio-merge">Combinar cambios de dispositivos</button>':''}<button class="text-button" data-personal="radio-refresh">Consultar copia de mi cuenta</button><small>${state.user?'Favoritos y listas sincronizados con tu cuenta.':'Inicia sesión para sincronizar tu música entre dispositivos.'}</small></div>`;}
function radioSongLibrary(t){return `<div class="song-library"><button class="icon-button" data-radio-favorite="${t.id}" aria-label="${radio.library.favorites.includes(t.id)?'Quitar de':'Añadir a'} favoritos: ${e(t.title)}" aria-pressed="${radio.library.favorites.includes(t.id)}">${radio.library.favorites.includes(t.id)?'♥':'♡'}</button><button class="icon-button" data-radio-add="${t.id}" aria-label="Añadir ${e(t.title)} a una lista">＋</button><button class="icon-button" data-radio-report="${t.id}" aria-label="Reportar datos de ${e(t.title)}" title="Reportar asociación o video">⚑</button></div>`;}
function manageRadioLists(track){
  const t=radio.tracks.find(t=>t.id===track);
  modal(`<h2>${t?'Guardar canción en una lista':'Mis listas de radio'}</h2>${t?`<p>${e(t.title)} · ${e(t.artist)} · ${e(t.anime)}</p>`:''}<form id="radio-list-create" data-track="${e(track||'')}"><label>Nombre de lista<input class="form-input" name="name" maxlength="60" required></label><button class="button primary">Crear lista</button></form><div class="radio-list-manager">${radio.library.lists.map(l=>`<section><strong>${e(l.name)} · ${l.ids.length} temas</strong><div class="toolbar">${t?`<button class="button ghost" data-radio-list-toggle="${l.id}" data-track="${t.id}">${l.ids.includes(t.id)?'Quitar canción':'Añadir canción'}</button>`:''}<button class="button danger" data-radio-list-delete="${l.id}">Eliminar lista</button></div></section>`).join('')||'<p>Todavía no tienes listas.</p>'}</div>`);
}
document.addEventListener('click',async event=>{
  const b=event.target.closest('[data-radio-library],[data-radio-favorite],[data-radio-add],[data-radio-list-toggle],[data-radio-list-delete]');if(!b)return;event.preventDefault();
  if(b.dataset.radioLibrary)manageRadioLists();
  if(b.dataset.radioAdd)manageRadioLists(b.dataset.radioAdd);
  if(b.dataset.radioFavorite){const id=b.dataset.radioFavorite;if(!radio.tracks.some(t=>t.id===id))return;radio.library.favorites=radio.library.favorites.includes(id)?radio.library.favorites.filter(n=>n!==id):[...radio.library.favorites,id].slice(-300);radio.storeLibrary();render();}
  if(b.dataset.radioListToggle){const l=radio.library.lists.find(l=>l.id===b.dataset.radioListToggle),id=b.dataset.track;if(!l||!radio.tracks.some(t=>t.id===id))return;l.ids=l.ids.includes(id)?l.ids.filter(n=>n!==id):[...l.ids,id].slice(-300);radio.storeLibrary();manageRadioLists(id);}
  if(b.dataset.radioListDelete&&await experienceConfirm('¿Eliminar esta lista de radio?')){radio.library.lists=radio.library.lists.filter(l=>l.id!==b.dataset.radioListDelete);if(radio.collection===b.dataset.radioListDelete)radio.collection='all';radio.storeLibrary();manageRadioLists();}
});
document.addEventListener('change',event=>{if(event.target.id==='radio-collection'){radio.pause();radio.collection=event.target.value;render();}});
document.addEventListener('submit',event=>{if(event.target.id!=='radio-list-create')return;event.preventDefault();if(radio.library.lists.length>=20){toast('Puedes guardar hasta veinte listas.',true);return;}const name=event.target.elements.name.value.trim();if(!name)return;const id=Array.from(crypto.getRandomValues(new Uint8Array(8)),n=>n.toString(16).padStart(2,'0')).join('');radio.library.lists.push({id,name,ids:[]});radio.storeLibrary();manageRadioLists(event.target.dataset.track);});
