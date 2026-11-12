'use strict';
const LIBRARY_FILE_LIMIT = 128 * 1024 * 1024;

function libraryImportChunks(library, maximum = 1024 * 1024) {
  if (!library || library.format !== 'seasonav1.library/v1' || !Array.isArray(library.entries) || !Array.isArray(library.watched))
    throw new Error('El archivo no es una biblioteca de YomaTV.');
  const slug = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,240}$/.test(value);
  for (const row of library.entries) {
    if (!row || !slug(row.slug) || !['watching','planned','completed','paused','dropped'].includes(row.status) ||
      typeof row.favorite !== 'boolean' || typeof row.excluded !== 'boolean' || !Number.isInteger(row.score) ||
      row.score < 0 || row.score > 10 || typeof row.notes !== 'string' || [...row.notes].length > 2000)
      throw new Error('Una ficha de la copia tiene datos inválidos. No se ha iniciado la importación.');
  }
  for (const row of library.watched) {
    if (!row || !slug(row.slug) || typeof row.number !== 'string' || !/^\d{1,5}(?:\.\d{1,4})?$/.test(row.number) ||
      (row.watched_at !== undefined && (!Number.isInteger(row.watched_at) || row.watched_at < 1 || row.watched_at > Date.now()/1000+600)))
      throw new Error('Un capítulo de la copia tiene datos inválidos. No se ha iniciado la importación.');
  }
  const encoder = new TextEncoder(), parts = [];
  const empty = () => ({ format: 'seasonav1.library/v1', entries: [], watched: [] });
  let part = empty(), bytes = 100;
  for (const kind of ['entries','watched']) for (const row of library[kind]) {
    const size = encoder.encode(JSON.stringify(row)).length + 1;
    if (size + 100 > maximum) throw new Error('Un registro supera el tamaño permitido.');
    if (bytes + size > maximum || part.entries.length >= 5000 || part.watched.length >= 50000) {
      parts.push(part); part = empty(); bytes = 100;
    }
    part[kind].push(row); bytes += size;
  }
  if (part.entries.length || part.watched.length || !parts.length) parts.push(part);
  if(library.extras){
    if(typeof library.extras!=='object'||Array.isArray(library.extras))throw new Error('Los datos adicionales son inválidos.');
    let extra={},extraBytes=100;
    const flush=()=>{if(Object.keys(extra).length)parts.push({...empty(),extras:extra});extra={};extraBytes=100;};
    for(const [kind,values] of Object.entries(library.extras)){
      if(kind==='player_preferences'){extra[kind]=values;continue;}
      if(!['intro','bookmark','collection','radio','options','positions','filters'].includes(kind)||!Array.isArray(values))throw new Error('Los datos adicionales contienen una sección inválida.');
      for(const row of values){const size=encoder.encode(JSON.stringify(row)).length+32;if(size>maximum-100)throw new Error('Un dato adicional supera el tamaño permitido.');if(size+extraBytes>maximum)flush();(extra[kind]||=[]).push(row);extraBytes+=size;}
    }flush();
  }

  return parts;
}
