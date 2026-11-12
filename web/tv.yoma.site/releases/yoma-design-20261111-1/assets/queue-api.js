'use strict';
function downloadPlan(plan) {
  const file = new Blob([JSON.stringify(plan, null, 2)], {
      type: 'application/json'
    }),
    url = URL.createObjectURL(file),
    a = document.createElement('a');
  a.href = url;
  a.download = `YomaTV-cola-${plan.created_at.slice(0, 10)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
async function sendToPC(ids, manual = false) {
  if(!ids)await ensureQueueHistory('',{all:true,active:true});
  if (!ids && !manual && bridge.connected && bridge.supports('live_status')) {
    ids = sendableJobs().map((j) => Number(j.id));
    if (!ids.length) {
      toast('Los capítulos ya están en la PC o terminados.');
      return;
    }
  }
  const r = await api('export', ids ? { job_ids: ids } : {});
  render();
  if (manual) {
    downloadPlan(r.plan);
    toast('Archivo de cola guardado. Usa Importar cola web en YomaTV.');
    return;
  }
  toast('Enviando la cola a YomaTV…');
  const sent = await bridge.deliver(r.plan, downloadPlan);
  render();
  toast(
    sent.direct
      ? `YomaTV recibió ${r.plan.items.length} ${r.plan.items.length === 1 ? 'capítulo' : 'capítulos'}. La descarga continúa en la bandeja.`
      : `${sent.message} Se descargó el JSON para importarlo manualmente.`,
    !sent.direct
  );
  if (sent.direct) scheduleResults(1000);
}
function activeJobs() {
  return state.jobs.filter((j) => ['pending', 'exported'].includes(j.status));
}
