/**
 * GlobalNavigation Hook
 * Handles global keyboard shortcuts for navigation between main pages.
 *
 * Shortcuts:
 * - Command+Shift+P: Navigate to Products page
 * - Command+Shift+S: Navigate to Sessions page
 */
export default {
  mounted() {
    this.handleKeydown = (e) => {
      // Pause keyboard control when typing in input fields
      const activeElement = document.activeElement
      const isTyping = activeElement && (
        activeElement.tagName === 'INPUT' ||
        activeElement.tagName === 'TEXTAREA' ||
        activeElement.isContentEditable
      )
      if (isTyping) return

      // Check for Command (Mac) or Ctrl (Windows/Linux) + Shift
      const modifierKey = e.metaKey || e.ctrlKey

      if (modifierKey && e.shiftKey) {
        switch (e.key.toUpperCase()) {
          case 'P':
            e.preventDefault()
            window.location.href = '/products'
            break

          case 'S':
            e.preventDefault()
            window.location.href = '/sessions'
            break
        }
      }
    }

    window.addEventListener("keydown", this.handleKeydown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown)
  }
}
