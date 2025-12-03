/**
 * Add collapse/expand functionality to large code blocks
 */
(function() {
  'use strict';

  // Minimum number of lines to show collapse button
  const MIN_LINES_THRESHOLD = 15;
  // Number of lines to show when collapsed
  const COLLAPSED_LINES = 10;

  function getLineCount(codeEl) {
    const text = codeEl.textContent || codeEl.innerText;
    return text.split('\n').length;
  }

  function addCollapseButton(containerEl) {
    const codeEl = containerEl.querySelector('pre');
    if (!codeEl) return;

    const lineCount = getLineCount(codeEl);
    
    // Only add collapse button if code block is large enough
    if (lineCount < MIN_LINES_THRESHOLD) return;

    // Create collapse button
    const collapseBtn = document.createElement('button');
    collapseBtn.className = 'collapse-code-button';
    collapseBtn.setAttribute('aria-label', 'Collapse code block');
    collapseBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"></polyline></svg>';
    
    let isCollapsed = false;

    collapseBtn.addEventListener('click', function() {
      isCollapsed = !isCollapsed;
      
      if (isCollapsed) {
        codeEl.classList.add('collapsed');
        collapseBtn.setAttribute('aria-label', 'Expand code block');
        collapseBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>';
      } else {
        codeEl.classList.remove('collapsed');
        collapseBtn.setAttribute('aria-label', 'Collapse code block');
        collapseBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"></polyline></svg>';
      }
    });

    // Insert button before the pre element
    containerEl.insertBefore(collapseBtn, codeEl);
    
    // Add line count indicator
    const lineIndicator = document.createElement('span');
    lineIndicator.className = 'code-line-count';
    lineIndicator.textContent = `${lineCount} lines`;
    containerEl.insertBefore(lineIndicator, codeEl);
  }

  // Add collapse button to large code blocks
  const highlightBlocks = document.querySelectorAll('div.highlighter-rouge, div.highlight, figure.highlight');
  Array.prototype.forEach.call(highlightBlocks, addCollapseButton);
})();
