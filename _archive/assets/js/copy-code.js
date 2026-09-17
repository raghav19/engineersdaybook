/**
 * Add copy buttons to code blocks
 */
(function() {
  'use strict';

  if (!document.queryCommandSupported('copy')) {
    return;
  }

  function flashCopyMessage(el, msg) {
    el.innerHTML = msg;
    setTimeout(function() {
      el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
    }, 1000);
  }

  function selectText(node) {
    var selection = window.getSelection();
    var range = document.createRange();
    range.selectNodeContents(node);
    selection.removeAllRanges();
    selection.addRange(range);
    return selection;
  }

  function addCopyButton(containerEl) {
    // Check if button already exists - check both data attribute and actual button presence
    if (containerEl.getAttribute('data-copy-button-added') || 
        containerEl.querySelector('.copy-code-button')) {
      return;
    }
    containerEl.setAttribute('data-copy-button-added', 'true');
    
    var copyBtn = document.createElement("button");
    copyBtn.className = "copy-code-button";
    copyBtn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
    copyBtn.setAttribute('aria-label', 'Copy code to clipboard');

    var codeEl = containerEl.firstElementChild;
    copyBtn.addEventListener('click', function() {
      try {
        var selection = selectText(codeEl);
        document.execCommand('copy');
        selection.removeAllRanges();

        flashCopyMessage(copyBtn, '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>')
      } catch(e) {
        console && console.log(e);
        flashCopyMessage(copyBtn, '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>')
      }
    });

    containerEl.appendChild(copyBtn);
  }

  // Add copy button to code blocks - be more specific to avoid nested duplicates
  var highlightBlocks = document.querySelectorAll('div.highlighter-rouge:not(.highlight div.highlighter-rouge), div.highlight:not(figure.highlight div.highlight), figure.highlight');
  
  // Additional safety: filter out any nested elements
  var topLevelBlocks = Array.prototype.filter.call(highlightBlocks, function(block) {
    // Check if this block is inside another highlight block
    var parent = block.parentElement;
    while (parent) {
      if (parent.classList && (parent.classList.contains('highlight') || 
          parent.classList.contains('highlighter-rouge') || 
          parent.tagName === 'FIGURE' && parent.classList.contains('highlight'))) {
        return false; // This is a nested block, skip it
      }
      parent = parent.parentElement;
    }
    return true; // This is a top-level block
  });
  
  Array.prototype.forEach.call(topLevelBlocks, addCopyButton);
})();
