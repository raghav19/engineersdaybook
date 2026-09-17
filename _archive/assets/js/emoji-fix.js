/**
 * Fix emoji colors in dark mode by wrapping them with .emoji class
 */
(function() {
  'use strict';

  // Emoji regex pattern - matches most common emoji
  var emojiRegex = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}\u{1F100}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{FE00}-\u{FE0F}\u{200D}\u{20E3}\u{231A}\u{231B}\u{23E9}-\u{23EC}\u{23F0}\u{23F3}\u{25FD}\u{25FE}\u{2614}\u{2615}\u{2648}-\u{2653}\u{267F}\u{2693}\u{26A1}\u{26AA}\u{26AB}\u{26BD}\u{26BE}\u{26C4}\u{26C5}\u{26CE}\u{26D4}\u{26EA}\u{26F2}\u{26F3}\u{26F5}\u{26FA}\u{26FD}\u{2705}\u{270A}\u{270B}\u{2728}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2795}-\u{2797}\u{27B0}\u{27BF}\u{2B1B}\u{2B1C}\u{2B50}\u{2B55}]/gu;

  function wrapEmojis(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      var text = node.textContent;
      if (emojiRegex.test(text)) {
        var span = document.createElement('span');
        span.innerHTML = text.replace(emojiRegex, function(match) {
          return '<span class="emoji">' + match + '</span>';
        });
        node.parentNode.replaceChild(span, node);
      }
    } else if (node.nodeType === Node.ELEMENT_NODE && 
               node.nodeName !== 'SCRIPT' && 
               node.nodeName !== 'STYLE' && 
               node.nodeName !== 'CODE' &&
               node.nodeName !== 'PRE' &&
               !node.classList.contains('emoji')) {
      Array.from(node.childNodes).forEach(wrapEmojis);
    }
  }

  // Run on DOM ready
  function init() {
    // Process the main content area
    var mainContent = document.querySelector('main, article, .post-content, body');
    if (mainContent) {
      wrapEmojis(mainContent);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
