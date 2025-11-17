# Vendored JavaScript Libraries

## SortableJS (sortable.js)

**Version:** 1.15.6
**License:** MIT
**Source:** https://github.com/SortableJS/Sortable

### Why Vendored?

This library is vendored (committed directly to the repository) rather than managed via npm for the following reasons:

1. **Simplicity**: Phoenix asset pipeline works out-of-the-box with vendored files without requiring additional npm build configuration
2. **Stability**: Locks the exact version to prevent unexpected behavior from automatic updates
3. **Offline Development**: Ensures the library is always available without external dependencies
4. **Build Performance**: Avoids npm install step in deployment pipeline

### When to Update

Check for updates periodically at the [SortableJS GitHub releases page](https://github.com/SortableJS/Sortable/releases). Download the latest version and replace `sortable.js` if needed.

### Alternative Approach

If the project grows to require many JavaScript dependencies, consider migrating to npm package management:

```bash
npm install sortablejs
```

Then import in `app.js`:
```javascript
import Sortable from 'sortablejs'
```
