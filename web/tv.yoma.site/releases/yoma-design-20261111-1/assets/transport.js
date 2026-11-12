'use strict';
// Explicit transport boundary: PHP calls never retry a mutation implicitly.
const SeasonTransport = (() => {
  const active = new Set(), keyed = new Map();
  let epoch = 0;
  async function request(url, options = {}, { timeout = 45000, key = '', signal, format = 'json' } = {}) {
    if (key) keyed.get(key)?.abort('superseded');
    const controller = new AbortController();
    let timedOut = false;
    const abort = () => controller.abort('cancelled');
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
    active.add(controller);
    if (key) keyed.set(key, controller);
    const timer = setTimeout(() => { timedOut = true; controller.abort('timeout'); }, timeout);
    try {
      const response = await fetch(url, { ...options, signal: controller.signal });
      // Include response decoding in the deadline, not just receipt of headers.
      if (format==='blob' && response.ok && !(response.headers.get('Content-Type')||'').includes('application/octet-stream')) throw new Error('Invalid backup response');
      const result = format==='blob' && response.ok ? await response.blob() : await response.json();
      return { response, result };
    } catch (cause) {
      const error = new Error(timedOut
        ? 'La solicitud tardó demasiado. Comprueba el estado antes de repetir un cambio.'
        : controller.signal.aborted ? 'Solicitud cancelada.'
          : 'No se pudo contactar con la web. Comprueba tu conexión.');
      error.name = timedOut ? 'TimeoutError' : controller.signal.aborted ? 'AbortError' : 'NetworkError';
      error.cancelled = controller.signal.aborted && !timedOut;
      error.cause = cause;
      throw error;
    } finally {
      clearTimeout(timer); active.delete(controller);
      signal?.removeEventListener('abort', abort);
      if (keyed.get(key) === controller) keyed.delete(key);
    }
  }
  function cancelAll() { epoch++; for (const controller of active) controller.abort('account-change'); }
  return { request, cancelAll, get epoch() { return epoch; } };
})();
