'use strict';
let installPrompt = null;
let waitingWebUpdate=null,webUpdateTimer=null;
function offerWebUpdate(){
  if(!waitingWebUpdate||document.querySelector('#web-update-notice'))return;
  if(typeof playerView!=='undefined'&&playerView&&!playerController?.latest.ended){clearTimeout(webUpdateTimer);webUpdateTimer=setTimeout(offerWebUpdate,10000);return;}
  const notice=document.createElement('aside');notice.id='web-update-notice';notice.className='web-update-notice';notice.setAttribute('role','status');notice.innerHTML='<span>Hay una versión nueva de YomaTV.</span><button class="button small primary" data-personal="update-app">Actualizar al salir del capítulo</button>';document.body.append(notice);
}
function activateWebUpdate(){
  if(!waitingWebUpdate)return;
  if(typeof playerView!=='undefined'&&playerView&&!playerController?.latest.ended){toast('La actualización estará disponible al terminar el capítulo.');return;}
  let done=false;navigator.serviceWorker.addEventListener('controllerchange',()=>{if(!done){done=true;location.reload();}},{once:true});waitingWebUpdate.postMessage({type:'ACTIVATE_UPDATE'});
}
window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  installPrompt = event;
});
async function installWebApp() {
  if (installPrompt) {
    await installPrompt.prompt();
    await installPrompt.userChoice;
    installPrompt = null;
  } else
    toast(
      'Usa «Instalar aplicación» o «Añadir a pantalla de inicio» en el menú del navegador. Si tu acceso antiguo muestra una letra, elimínalo y vuelve a crearlo para renovar el icono.'
    );
}
if (
  'serviceWorker' in navigator &&
  (location.protocol === 'https:' || location.hostname === '127.0.0.1')
)
  navigator.serviceWorker.register('service-worker.php').then(async registration => {
    if(registration.waiting){waitingWebUpdate=registration.waiting;offerWebUpdate();}
    registration.addEventListener('updatefound',()=>{const worker=registration.installing;worker?.addEventListener('statechange',()=>{if(worker.state==='installed'&&navigator.serviceWorker.controller){waitingWebUpdate=registration.waiting||worker;offerWebUpdate();}});});
    await navigator.serviceWorker.ready;
    // The public index is safe to store; never prefetch a personal API response.
    if (navigator.serviceWorker.controller) fetch('catalog-public.php',{cache:'no-cache'}).catch(()=>{});
    else navigator.serviceWorker.addEventListener('controllerchange',()=>fetch('catalog-public.php',{cache:'no-cache'}).catch(()=>{}),{once:true});
  }).catch(() => {});
window.addEventListener('offline', () => {
  toast('Sin conexión. Puedes abrir el catálogo guardado.');
  if (document.querySelector('#offline-banner')) return;
  const banner = document.createElement('aside');
  banner.className = 'offline-banner';
  banner.id = 'offline-banner';
  banner.innerHTML =
    '<span>Sin conexión · catálogo público disponible</span><a href="releases/yoma-design-20261111-1/offline.html">Abrir catálogo guardado</a>';
  document.body.append(banner);
});
window.addEventListener('online', () =>
  document.querySelector('#offline-banner')?.remove()
);
