// Hudson JavaScript Hooks for LiveView

const Hooks = {}

/**
 * KeyboardControl Hook
 * Handles keyboard navigation for the session run view.
 *
 * Primary Navigation (Direct Jumps):
 * - Type number digits (0-9) to build a product number
 * - Press Enter to jump to that product
 * - Home/End to jump to first/last
 *
 * Convenience Navigation (Sequential):
 * - Arrow keys (↑↓) for previous/next product
 * - Arrow keys (←→) for previous/next image
 * - Space for next product
 */
Hooks.KeyboardControl = {
  mounted() {
    this.jumpBuffer = ""
    this.jumpTimeout = null

    this.handleKeydown = (e) => {
      // Prevent default for navigation keys to avoid scrolling
      const navKeys = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Home', 'End']
      if (navKeys.includes(e.code)) {
        e.preventDefault()
      }

      switch (e.code) {
        // PRIMARY NAVIGATION: Jump to first/last
        case 'Home':
          this.pushEvent("jump_to_first", {})
          break

        case 'End':
          this.pushEvent("jump_to_last", {})
          break

        // CONVENIENCE: Sequential product navigation with arrow keys
        case 'ArrowDown':
        case 'KeyJ':
          this.pushEvent("next_product", {})
          break

        case 'ArrowUp':
        case 'KeyK':
          this.pushEvent("previous_product", {})
          break

        case 'Space':
          e.preventDefault() // Prevent page scroll
          this.pushEvent("next_product", {})
          break

        // IMAGE navigation (always sequential)
        case 'ArrowRight':
        case 'KeyL':
          this.pushEvent("next_image", {})
          break

        case 'ArrowLeft':
        case 'KeyH':
          this.pushEvent("previous_image", {})
          break

        default:
          // PRIMARY NAVIGATION: Number input for jump-to-product
          if (e.key >= '0' && e.key <= '9') {
            this.handleNumberInput(e.key)
          } else if (e.code === 'Enter' && this.jumpBuffer) {
            this.pushEvent("jump_to_product", {position: this.jumpBuffer})
            this.jumpBuffer = ""
            this.updateJumpDisplay("")
            clearTimeout(this.jumpTimeout)
          } else if (e.code === 'Escape' && this.jumpBuffer) {
            // Clear buffer on Escape
            this.jumpBuffer = ""
            this.updateJumpDisplay("")
            clearTimeout(this.jumpTimeout)
          }
      }
    }

    this.handleNumberInput = (digit) => {
      this.jumpBuffer += digit

      // Update visual feedback
      this.updateJumpDisplay(this.jumpBuffer)

      // Clear buffer after 2 seconds of inactivity
      clearTimeout(this.jumpTimeout)
      this.jumpTimeout = setTimeout(() => {
        this.jumpBuffer = ""
        this.updateJumpDisplay("")
      }, 2000)
    }

    this.updateJumpDisplay = (value) => {
      // Show the current jump buffer (could be enhanced with a visible indicator)
      console.log("Jump to:", value || "(cleared)")
    }

    window.addEventListener("keydown", this.handleKeydown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown)
    clearTimeout(this.jumpTimeout)
  }
}

/**
 * ConnectionStatus Hook
 * Shows connection status indicator for real-time sync.
 */
Hooks.ConnectionStatus = {
  mounted() {
    window.addEventListener("phx:page-loading-start", () => {
      this.el.innerHTML = '<span class="reconnecting">● Reconnecting...</span>'
    })

    window.addEventListener("phx:page-loading-stop", () => {
      this.el.innerHTML = '<span class="connected">● Connected</span>'
    })

    // Handle disconnection
    window.addEventListener("phx:disconnected", () => {
      this.el.innerHTML = '<span class="disconnected">● Disconnected</span>'
    })

    // Handle successful connection
    window.addEventListener("phx:connected", () => {
      this.el.innerHTML = '<span class="connected">● Connected</span>'
    })
  }
}

/**
 * ImageLoadingState Hook (for future LQIP implementation)
 * Manages progressive image loading with blur-to-sharp transition.
 */
Hooks.ImageLoadingState = {
  mounted() {
    const mainImage = this.el
    const placeholderId = `placeholder-${mainImage.id}`
    const skeletonId = `skeleton-${mainImage.id}`
    const placeholder = document.getElementById(placeholderId)
    const skeleton = document.getElementById(skeletonId)

    // Handle main image load
    const handleLoad = () => {
      mainImage.setAttribute('data-js-loading', 'false')
      if (placeholder) {
        placeholder.setAttribute('data-js-placeholder-loaded', 'true')
      }
      this.pushEvent("image_loaded", {id: mainImage.id})
    }

    mainImage.addEventListener('load', handleLoad)

    // Handle placeholder load (hide skeleton)
    if (placeholder) {
      placeholder.addEventListener('load', () => {
        if (skeleton) skeleton.style.display = 'none'
      })
    }

    // Trigger load if already cached
    if (mainImage.complete) {
      handleLoad()
    }
  },

  beforeUpdate() {
    // Reset loading state when src changes
    this.el.setAttribute('data-js-loading', 'true')
  }
}

export default Hooks
