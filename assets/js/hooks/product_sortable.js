// ProductSortable Hook
// Enables drag-and-drop reordering of products within session cards

import Sortable from "../../vendor/sortable"

export default {
  mounted() {
    const hook = this
    let dragStarted = false
    let cleanupTimer = null

    // Safety reset: clear drag state if user releases mouse outside the drag area
    const handleGlobalMouseUp = () => {
      if (dragStarted && cleanupTimer) {
        clearTimeout(cleanupTimer)
        cleanupTimer = setTimeout(() => {
          dragStarted = false
        }, 100)
      }
    }

    document.addEventListener('mouseup', handleGlobalMouseUp)
    document.addEventListener('touchend', handleGlobalMouseUp)

    // Initialize SortableJS on this element
    const sortable = new Sortable(this.el, {
      animation: 150,           // Smooth animation duration in ms
      delay: 0,                 // No delay on desktop
      delayOnTouchOnly: true,   // Small delay on touch devices to prevent accidental drags
      touchStartThreshold: 5,   // px before drag starts on touch devices

      // CSS classes applied during drag states
      dragClass: "sortable-drag",      // Class on item being dragged
      ghostClass: "sortable-ghost",    // Class on placeholder/ghost element
      chosenClass: "sortable-chosen",  // Class when item is selected

      forceFallback: false,     // Use native HTML5 DnD when available

      // Track when drag starts
      onStart: (evt) => {
        dragStarted = true
        // Clear any pending cleanup timers
        if (cleanupTimer) {
          clearTimeout(cleanupTimer)
          cleanupTimer = null
        }
      },

      // Callback fired when drag operation ends
      onEnd: (evt) => {
        // Keep dragStarted true briefly to catch any subsequent click events
        // that fire as a result of the drag ending
        cleanupTimer = setTimeout(() => {
          dragStarted = false
          cleanupTimer = null
        }, 100)

        // evt.oldIndex = original position (0-based index)
        // evt.newIndex = new position (0-based index)

        // Only send reorder event if position actually changed
        if (evt.oldIndex !== evt.newIndex) {
          // Collect all session_product IDs in their new order
          // Filter out elements without data-id (like the add button)
          const productIds = Array.from(this.el.children)
            .map(el => el.dataset.id)
            .filter(id => id !== undefined && id !== null)

          // Get session ID from the container's data attribute
          const sessionId = this.el.dataset.sessionId

          // Send reorder event to LiveView
          this.pushEventTo(this.el, "reorder_products", {
            session_id: sessionId,
            product_ids: productIds,
            old_index: evt.oldIndex,
            new_index: evt.newIndex
          })
        }
      }
    })

    // Add click handler to product items
    const handleProductClick = (event) => {
      // Ignore clicks that occurred during or immediately after a drag
      if (dragStarted) {
        event.preventDefault()
        event.stopPropagation()
        return
      }

      // Find the closest product item
      const productItem = event.target.closest('.session-card__product-item')
      if (!productItem) {
        return
      }

      // Don't handle clicks on the remove button
      if (event.target.closest('.session-card__product-actions')) {
        return
      }

      // Prevent event from bubbling to parent session card accordion
      event.stopPropagation()
      event.preventDefault()

      // Get product ID and send event to LiveView
      const productId = productItem.dataset.productId
      if (productId) {
        hook.pushEventTo(hook.el, "show_edit_product_modal", {
          "product-id": productId
        })
      }
    }

    // Attach click listener to the container
    this.el.addEventListener('click', handleProductClick)

    // Store for cleanup
    this.sortable = sortable
    this.handleProductClick = handleProductClick
    this.handleGlobalMouseUp = handleGlobalMouseUp
    this.cleanupTimer = cleanupTimer
  },

  // Cleanup when LiveView disconnects temporarily
  disconnected() {
    if (this.cleanupTimer) {
      clearTimeout(this.cleanupTimer)
      this.cleanupTimer = null
    }
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
    if (this.handleProductClick) {
      this.el.removeEventListener('click', this.handleProductClick)
      this.handleProductClick = null
    }
    if (this.handleGlobalMouseUp) {
      document.removeEventListener('mouseup', this.handleGlobalMouseUp)
      document.removeEventListener('touchend', this.handleGlobalMouseUp)
      this.handleGlobalMouseUp = null
    }
  },

  // Reinitialize when LiveView reconnects
  reconnected() {
    // Re-mount the sortable on reconnection
    this.mounted()
  },

  // Cleanup when the element is removed from the DOM permanently
  destroyed() {
    if (this.cleanupTimer) {
      clearTimeout(this.cleanupTimer)
      this.cleanupTimer = null
    }
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
    if (this.handleProductClick) {
      this.el.removeEventListener('click', this.handleProductClick)
      this.handleProductClick = null
    }
    if (this.handleGlobalMouseUp) {
      document.removeEventListener('mouseup', this.handleGlobalMouseUp)
      document.removeEventListener('touchend', this.handleGlobalMouseUp)
      this.handleGlobalMouseUp = null
    }
  }
}
