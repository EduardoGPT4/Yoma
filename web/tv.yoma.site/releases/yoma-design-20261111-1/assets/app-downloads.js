'use strict';
let appReleases=null,appReleasePromise=null;
// Android es la app Yoma (YomaTV y YomaShi); Windows sigue siendo el descargador de YomaTV.
const APP_REPOSITORIES={android:'EduardoGPT4/Yoma',windows:'EduardoGPT4/YomaTV'};
const APP_ASSETS={android:/^Yoma-([0-9.]+)-arm64\.apk$/,windows:/^YomaTV-Windows-([0-9.]+)\.exe$/};
const APP_REPOSITORY=APP_REPOSITORIES.android;
function validAppRelease(row){
  const repository=row&&APP_REPOSITORIES[row.platform];
  return Boolean(repository)&&typeof row.version==='string'&&/^[0-9.]{3,30}$/.test(row.version)&&Number.isSafeInteger(row.bytes)&&row.bytes>0&&row.bytes<300000000&&typeof row.url==='string'&&row.url.startsWith('https://github.com/'+repository+'/releases/download/')&&/^[a-zA-Z0-9._\/-]+$/.test(row.url.slice('https://github.com/'.length));
}
function appDownloadsView(){
  if(typeof yomaNative==='function'&&yomaNative())return '';
  if(!appReleasePromise)appReleasePromise=loadAppReleases();
  const rows=(appReleases||[]).filter(validAppRelease);
  return `<section class="app-download-section" aria-labelledby="app-download-heading"><div><p class="eyebrow">YOMA CONTIGO</p><h2 id="app-download-heading">Tus historias, en tu dispositivo.</h2><p>Yoma para Android reúne YomaTV y YomaShi: anime y manga sin conexión. Windows para descargar, organizar y automatizar tu biblioteca.</p></div><div class="app-download-options">${['android','windows'].map(platform=>{const r=rows.find(x=>x.platform===platform);return `<article><span class="app-platform">${platform==='android'?'Android · APK':'Windows · EXE'}</span><h3>${platform==='android'?'Yoma: anime y manga':'Tu biblioteca en la PC'}</h3><p>${platform==='android'?'YomaTV y YomaShi · Reanudación · Solo Wi-Fi':'Descargador portátil · Cola web · Temporada opcional'}</p>${r?`<a class="button ${platform==='android'?'primary':'ghost'}" href="${e(r.url)}" data-app-download="${platform}" rel="noopener">${icon('download')}Descargar para ${platform==='android'?'Android':'Windows'}</a><small>Versión ${e(r.version)} · ${(r.bytes/1000000).toLocaleString('es-MX',{maximumFractionDigits:1})} MB</small>`:'<span class="muted" role="status">Consultando la versión publicada…</span>'}</article>`;}).join('')}</div><a class="text-button" href="https://github.com/${APP_REPOSITORY}/releases" target="_blank" rel="noopener noreferrer">Versiones y notas de cambios ↗</a></section>`;
}
async function loadAppReleases(){
  // Cada plataforma se actualiza por separado: si GitHub no responde para una,
  // se conserva la versión verificada que trae la web.
  function apply(rows){
    if(!Array.isArray(rows))return;
    const next=[...(appReleases||[])];
    for(const row of rows.filter(validAppRelease)){
      const index=next.findIndex(x=>x.platform===row.platform);
      if(index>=0)next[index]=row;else next.push(row);
    }
    appReleases=next;
    const section=document.querySelector('.app-download-section');if(section)section.outerHTML=appDownloadsView();
  }
  try{
    // Bundled, verified metadata remains usable when GitHub's API is rate limited.
    const script=document.querySelector('script[src*="releases/yoma-design-20261111-1/assets/app-downloads.js"]');
    const r=await fetch(new URL('app-releases.json',script?.src||new URL('releases/yoma-design-20261111-1/assets/app-downloads.js',location.href)),{credentials:'omit',cache:'no-cache'});
    if(r.ok)apply((await r.json()).apps);
  }catch{}
  await Promise.all(Object.entries(APP_REPOSITORIES).map(async([platform,repository])=>{
    try{
      const r=await fetch('https://api.github.com/repos/'+repository+'/releases/latest',{credentials:'omit',headers:{Accept:'application/vnd.github+json'},signal:AbortSignal.timeout(8000)});if(!r.ok)return;
      const release=await r.json();if(release.draft||release.prerelease)return;
      const pattern=APP_ASSETS[platform],a=release.assets?.find(a=>pattern.test(a.name));
      if(a)apply([{platform,version:a.name.match(pattern)[1],bytes:a.size,url:a.browser_download_url}]);
    }catch{}
  }));
}
