'use strict';
const themePreferences = { theme: 'dark', accent: 'vermilion', density: 'normal' };
try {
  const saved = JSON.parse(localStorage.getItem('seasonav1.appearance') || '{}');
  if (['dark', 'light', 'system'].includes(saved.theme)) themePreferences.theme = saved.theme;
  if (saved.design === 'medianoche' && ['compact', 'normal'].includes(saved.density))
    themePreferences.density = saved.density;
} catch {}
function applyAppearance() {
  document.documentElement.dataset.theme = themePreferences.theme === 'system'
    ? matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'
    : themePreferences.theme;
  document.documentElement.dataset.accent = 'vermilion';
  document.documentElement.dataset.density = themePreferences.density;
}
function setAppearance(key, value) {
  if (key === 'theme' && ['dark', 'light', 'system'].includes(value) ||
      key === 'density' && ['compact', 'normal'].includes(value)) {
    themePreferences[key] = value;
    try { localStorage.setItem('seasonav1.appearance', JSON.stringify({ ...themePreferences, design: 'medianoche' })); } catch {}
    applyAppearance();
  }
}
matchMedia('(prefers-color-scheme: light)').addEventListener('change', applyAppearance);
applyAppearance();
