'use strict';
let installPrompt = null;
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
      'Usa «Instalar aplicación» en el menú de Brave. En el celular, añade esta web a la pantalla de inicio.'
    );
}
if (
  'serviceWorker' in navigator &&
  (location.protocol === 'https:' || location.hostname === '127.0.0.1')
)
  navigator.serviceWorker.register('sw.js').then(async registration => {
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
    '<span>Sin conexión · catálogo público disponible</span><a href="offline.html">Abrir catálogo guardado</a>';
  document.body.append(banner);
});
window.addEventListener('online', () =>
  document.querySelector('#offline-banner')?.remove()
);
