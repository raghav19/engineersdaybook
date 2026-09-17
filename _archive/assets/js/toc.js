// Generate Table of Contents dynamically
document.addEventListener('DOMContentLoaded', function() {
  const article = document.querySelector('article');
  const tocContainer = document.getElementById('toc-container');
  
  if (!article || !tocContainer) return;
  
  // Find all headings h2-h6 in the article
  const headings = article.querySelectorAll('h2, h3, h4, h5, h6');
  
  if (headings.length === 0) {
    tocContainer.style.display = 'none';
    return;
  }
  
  // Create TOC list
  const tocList = document.createElement('ul');
  tocList.id = 'markdown-toc';
  
  headings.forEach(function(heading, index) {
    // Add an ID to the heading if it doesn't have one
    if (!heading.id) {
      heading.id = 'heading-' + index;
    }
    
    // Create list item
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = '#' + heading.id;
    a.textContent = heading.textContent;
    
    // Add indentation based on heading level
    const level = parseInt(heading.tagName.substring(1));
    if (level > 2) {
      li.style.marginLeft = (level - 2) + 'rem';
    }
    
    li.appendChild(a);
    tocList.appendChild(li);
  });
  
  // Append to container
  tocContainer.appendChild(tocList);
});
