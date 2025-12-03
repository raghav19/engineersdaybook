/**
 * Theme Switcher - Toggle between light, dark, and auto modes
 */
(function() {
  'use strict';

  const THEME_KEY = 'theme-preference';
  const body = document.body;

  // Get current theme from localStorage or body attribute
  function getCurrentTheme() {
    return localStorage.getItem(THEME_KEY) || body.getAttribute('a') || 'auto';
  }

  // Set theme and save to localStorage
  function setTheme(theme) {
    body.setAttribute('a', theme);
    localStorage.setItem(THEME_KEY, theme);
    updateButton(theme);
  }

  // Update button icon based on current theme
  function updateButton(theme) {
    const btn = document.getElementById('theme-toggle');
    if (!btn) return;

    const icons = {
      light: '☀️',
      dark: '🌙',
      auto: '⚙️'
    };

    btn.textContent = icons[theme] || icons.auto;
    btn.setAttribute('aria-label', `Current theme: ${theme}. Click to change.`);
    btn.setAttribute('title', `Theme: ${theme}`);
  }

  // Cycle through themes: auto -> light -> dark -> auto
  function cycleTheme() {
    const current = getCurrentTheme();
    const themes = ['auto', 'light', 'dark'];
    const currentIndex = themes.indexOf(current);
    const nextIndex = (currentIndex + 1) % themes.length;
    setTheme(themes[nextIndex]);
  }

  // Initialize theme on page load
  function init() {
    const savedTheme = localStorage.getItem(THEME_KEY);
    if (savedTheme) {
      setTheme(savedTheme);
    } else {
      updateButton(getCurrentTheme());
    }

    // Add click handler to button
    const btn = document.getElementById('theme-toggle');
    if (btn) {
      btn.addEventListener('click', cycleTheme);
    }
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
