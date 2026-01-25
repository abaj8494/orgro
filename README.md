# orgro fork

a heavily modified fork of [amake/orgro](https://github.com/amake/orgro) — the org mode viewer for ios and android.

this fork diverges substantially from upstream. it's built around how i actually use org files: nested in folders, linked together with transclusions, and synced via git.

## what's changed

### folder-first navigation

the start screen is now a proper folder explorer. no more hunting through a flat list of recent files — just navigate your directory tree directly.

- configured folder becomes your home base
- recent/starred files moved to a navigation drawer (hamburger menu)
- breadcrumb navigation with home and up buttons
- a-z/z-a sorting
- back button walks up the folder hierarchy before exiting

### file search

fuzzy search across all `.org` files in your configured folder. searches recursively, highlights matched characters, and sorts results by relevance.

### transclusion support

`#+transclude:` directives now work. point them at headings via id links or file paths and the content renders inline.

- supports `:only-contents` and `:no-first-heading` properties
- tap the header to collapse/expand
- long-press to jump to source
- handles circular references
- caches resolved content

### reader drawer

swipe from the left edge (or tap the menu) whilst viewing a document to open the reader drawer. shows the current folder's contents and recent files — switch between documents without leaving the reader.

### sibling navigation

double-swipe left/right to move between files in the same folder. single swipes still cycle todo states.

### git symlink support

paths like `[[file:img/photo.jpg]]` now resolve properly when `img` is a git portable symlink (a text file containing the target path). useful if you sync org files via github on systems without native symlink support.

## building

```bash
# clone
git clone https://github.com/abaj8494/orgro.git
cd orgro

# run
make run

# test
make test
```

## upstream

this fork tracks [amake/orgro](https://github.com/amake/orgro). the symlink fix has been submitted as a [pull request](https://github.com/amake/orgro/pull/188) — the rest of the changes are too opinionated for upstream.

## licence

same as upstream — gpl-3.0.
