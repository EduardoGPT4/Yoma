'use strict';
// El código permanece en este navegador. No se incluye en solicitudes PHP.
class SeasonBridge {
  constructor(port = 47653) {
    this.base =
      'http://127.0.0.1:' +
      (Number.isInteger(port) && port >= 1024 && port <= 65535 ? port : 47653);
    this.key = 'seasonav1.bridge.v1';
    this.token = '';
    try {
      this.token = localStorage.getItem(this.key) || '';
    } catch (_) {}
    this.connected = false;
    this.capabilities = [];
  }
  async request(path, body, token = this.token, timeout = 60000) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token))
      throw new Error('Empareja YomaTV con el código de tu PC.');
    const controller = new AbortController(),
      timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await fetch(this.base + path, {
        method: body ? 'POST' : 'GET',
        mode: 'cors',
        credentials: 'omit',
        cache: 'no-store',
        redirect: 'error',
        targetAddressSpace: 'loopback',
        headers: {
          Authorization: 'Bearer ' + token,
          ...(body ? { 'Content-Type': 'application/json' } : {})
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: controller.signal
      });
      const result = await response.json();
      if (!response.ok || !result.ok)
        throw new Error(
          result.message || 'YomaTV no pudo aceptar la cola.'
        );
      this.connected = true;
      return result;
    } catch (error) {
      this.connected = false;
      if (error instanceof TypeError || error.name === 'AbortError')
        throw new Error(
          'No se pudo conectar con YomaTV. Abre la app en este equipo y permite el acceso a la red local.'
        );
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }
  async pair(code) {
    const token = code.trim(),
      result = await this.request('/ping', undefined, token);
    if (!['SeasonAV1','YomaTV'].includes(result.app) || result.protocol !== 'seasonav1.bridge/v1')
      throw new Error('El servicio local no es compatible con esta versión.');
    try {
      localStorage.setItem(this.key, token);
    } catch (_) {
      throw new Error(
        'Permite el almacenamiento de este sitio para recordar el emparejamiento.'
      );
    }
    this.token = token;
    return result;
  }
  async ping() {
    const result = await this.request('/ping', undefined, this.token, 3500);
    if (!['SeasonAV1','YomaTV'].includes(result.app) || result.protocol !== 'seasonav1.bridge/v1')
      throw new Error('Actualiza YomaTV para conectar con esta web.');
    this.info=result;
    this.capabilities = Array.isArray(result.capabilities)
      ? result.capabilities
      : [];
    return result;
  }
  supports(feature) {
    return this.capabilities.includes(feature);
  }
  settings(preferences) {
    return this.request(
      '/settings',
      { format: 'seasonav1.web-settings/v1', preferences },
      this.token,
      30000
    );
  }
  status(installation, ids) {
    return this.request(
      '/status?' + new URLSearchParams({ installation, ids: ids.join(',') }),
      undefined,
      this.token,
      8000
    );
  }
  control(installation,ids,action,extra={}) {
    return this.request('/control',{format:'seasonav1.web-control/v1',installation,ids,action,...extra});
  }
  files(installation,ids) {return this.request('/files',{installation,ids});}
  forget() {
    this.info=null;
    this.token = '';
    this.connected = false;
    this.capabilities = [];
    try {
      localStorage.removeItem(this.key);
    } catch (_) {}
  }
  async deliver(plan, download) {
    if (this.token) {
      try {
        return { direct: true, result: await this.request('/queue', plan) };
      } catch (error) {
        download(plan);
        return { direct: false, message: error.message };
      }
    }
    download(plan);
    return {
      direct: false,
      message:
        'Empareja tu PC para enviarla automáticamente. Se guardó el archivo de cola.'
    };
  }
  results(installation, ids) {
    return this.request(
      '/results?' +
        new URLSearchParams({
          installation,
          ...(ids && this.supports('filtered_results')
            ? { ids: ids.join(',') }
            : {})
        }),
      undefined,
      this.token,
      8000
    );
  }
}
