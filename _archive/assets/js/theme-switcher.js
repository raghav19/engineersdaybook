/**
 * Theme Switcher - Toggle between light and dark modes
 */
(function() {
  'use strict';

  const THEME_KEY = 'theme-preference';
  const body = document.body;

  // Get current theme from localStorage or body attribute
  function getCurrentTheme() {
    const saved = localStorage.getItem(THEME_KEY);
    if (saved === 'light' || saved === 'dark') {
      return saved;
    }
    
    // Default to system preference
    const bodyTheme = body.getAttribute('a');
    if (bodyTheme === 'light' || bodyTheme === 'dark') {
      return bodyTheme;
    }
    
    // Detect system preference
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      return 'dark';
    }
    return 'light';
  }

  // Set theme and save to localStorage
  function setTheme(theme) {
    body.setAttribute('a', theme);
    localStorage.setItem(THEME_KEY, theme);
    updateButton(theme);
  }

  // Update button icon to show the OPPOSITE theme (what clicking will switch to)
  function updateButton(currentTheme) {
    const btn = document.getElementById('theme-toggle');
    if (!btn) return;

    // Show moon if currently light (will switch to dark)
    // Show sun if currently dark (will switch to light)
    if (currentTheme === 'light') {
      btn.textContent = '🌙';
      btn.setAttribute('aria-label', 'Switch to dark mode');
      btn.setAttribute('title', 'Switch to dark mode');
    } else {
      btn.textContent = '☀️';
      btn.setAttribute('aria-label', 'Switch to light mode');
      btn.setAttribute('title', 'Switch to light mode');
    }
  }

  // Toggle between light and dark
  function toggleTheme() {
    const current = getCurrentTheme();
    const newTheme = current === 'light' ? 'dark' : 'light';
    setTheme(newTheme);
  }

  // Initialize theme on page load
  function init() {
    const currentTheme = getCurrentTheme();
    setTheme(currentTheme);

    // Add click handler to button
    const btn = document.getElementById('theme-toggle');
    if (btn) {
      btn.addEventListener('click', toggleTheme);
    }
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
