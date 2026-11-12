'use strict';
const themePreferences = { theme: 'dark', accent: 'mint', density:'compact' };
try {
  const saved = JSON.parse(
    localStorage.getItem('seasonav1.appearance') || '{}'
  );
  if (['dark', 'light', 'system'].includes(saved.theme))
    themePreferences.theme = saved.theme;
  if(['compact','normal'].includes(saved.density))themePreferences.density=saved.density;
  if (['mint', 'blue', 'rose', 'violet'].includes(saved.accent))
    themePreferences.accent = saved.accent;
} catch {}
function applyAppearance() {
  document.documentElement.dataset.theme =
    themePreferences.theme === 'system'
      ? matchMedia('(prefers-color-scheme: light)').matches
        ? 'light'
        : 'dark'
      : themePreferences.theme;
  document.documentElement.dataset.accent = themePreferences.accent;
  document.documentElement.dataset.density=themePreferences.density;
}
function setAppearance(key, value) {
  if (
    !['theme','accent','density'].includes(key) ||
    (key==='density'&&!['compact','normal'].includes(value)) ||
    (key === 'theme' && !['dark', 'light', 'system'].includes(value)) ||
    (key === 'accent' && !['mint', 'blue', 'rose', 'violet'].includes(value))
  )
    return;
  themePreferences[key] = value;
  try {
    localStorage.setItem(
      'seasonav1.appearance',
      JSON.stringify(themePreferences)
    );
  } catch {}
  applyAppearance();
}
matchMedia('(prefers-color-scheme: light)').addEventListener(
  'change',
  applyAppearance
);
applyAppearance();
// Read the desktop layout before styles load, avoiding a sidebar flash on reload.
try {
  document.documentElement.dataset.sidebarCollapsed =
    localStorage.getItem('seasonav1.sidebarCollapsed') === 'true'
      ? 'true'
      : 'false';
} catch {}
