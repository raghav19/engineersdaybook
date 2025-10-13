# Project Structure

This document explains the organization of the engineersdaybook Jekyll site.

## Folder Organization

### `/pages/`
Contains standalone pages (about, categories, etc.)
- `about.md` - Personal profile/CV page (accessible at `/about.html`)
- `categories.md` - Category overview page (accessible at `/categories.html`)

**Note:** Each page includes a `permalink` in front matter to maintain consistent URLs regardless of file location.

### `/archives/`
Contains category-specific archive pages
- `archive.md` - Main archive page
- `devsecops-archive.md` - DevSecOps category archive
- `kubernetes-archive.md` - Kubernetes category archive
- `security-archive.md` - Security category archive
- `example2-archive.md` - Example archive
- `index.md` - Archives index page

### `/images/`
Contains site images and assets
- `logo.png` - Site favicon/logo

### `/_posts/`
Blog posts in markdown format
- Named as `YYYY-MM-DD-title.md`
- Automatically processed by Jekyll

### `/_layouts/`
Jekyll layout templates
- `default.html` - Base layout
- `home.html` - Homepage layout
- `post.html` - Individual post layout
- `page.html` - Static page layout
- `archive.html` - Archive page layout

### `/_includes/`
Reusable template components
- `head.html` - HTML head section
- `social_links.html` - Social media icons (references `/about.html`)
- `related_posts.html` - Related posts section
- `toc.html` - Table of contents
- `menu_item.html` - Menu item template
- `post_list.html` - Post list component
- `back_link.html` - Back navigation link
- `goat_counter.html` - Analytics tracking

### `/assets/`
Static assets (CSS, JavaScript)
- `/css/` - Stylesheets
- `/js/` - JavaScript files (TOC generator, search, etc.)

### `/_data/`
Site data files
- `menu.yml` - Navigation menu configuration

### `/_sass/`
SCSS/Sass stylesheets
- `no-style-please.scss` - Theme styles

## Configuration Files

- `_config.yml` - Main Jekyll configuration
  - Updated `favicon` path to `images/logo.png`
  - Contains site metadata and theme settings
- `Gemfile` - Ruby dependencies
- `.gitignore` - Git ignore rules

## How It Works

1. **Jekyll processes all files** in the root and subdirectories (except those starting with `_` or listed in excludes)
2. **Permalinks maintain URL structure** - Moving files to folders doesn't break links because we use `permalink:` in front matter
3. **References use `relative_url`** - All internal links use Liquid's `relative_url` filter, making them work regardless of baseurl
4. **Archives linking** - Category archives are linked via `/archives/category-name-archive.html` pattern

## Benefits of This Structure

✅ **Cleaner root directory** - Less clutter in the main folder  
✅ **Logical grouping** - Related files organized together  
✅ **Easier maintenance** - Know exactly where to find each type of content  
✅ **Backward compatible** - All existing URLs continue to work  
✅ **Scalable** - Easy to add more pages or images without cluttering root
