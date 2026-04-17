import { Controller } from "@hotwired/stimulus";

/**
 * Connects to data-controller="lazy-load"
 * Used with <details> elements to lazy-load content when expanded
 * Use data-action="toggle->lazy-load#toggled" on the <details> element
 * Optional: data-lazy-load-auto-open-param-value="paramName" to auto-open when ?paramName=1 is in URL
 */
export default class extends Controller {
  /** @type {string[]} */
  static targets = ["content", "loading", "frame"];

  /** @type {Object.<string, any>} */
  static values = { url: String, loaded: Boolean, autoOpenParam: String };

  /** @type {boolean} */
  loading = false;

  /**
   * Initialize controller and check for auto-open params
   * @returns {void}
   */
  connect() {
    // Check if we should auto-open based on URL param
    if (this.hasAutoOpenParamValue && this.autoOpenParamValue) {
      const params = new URLSearchParams(window.location.search);
      if (params.get(this.autoOpenParamValue) === "1") {
        this.element.open = true;
        // Clean up the URL param after opening
        params.delete(this.autoOpenParamValue);
        const newUrl = params.toString()
          ? `${window.location.pathname}?${params.toString()}${window.location.hash}`
          : `${window.location.pathname}${window.location.hash}`;
        window.history.replaceState({}, "", newUrl);
      }
    }

    // If already open on connect (browser restored state), load immediately
    if (this.element.open && !this.loadedValue) {
      this.load();
    }
  }

  /**
   * Handle toggle event from <details> element
   * @returns {void}
   */
  toggled() {
    if (this.element.open && !this.loadedValue) {
      this.load();
    }
  }

  /**
   * Load content from the server via fetch
   * @returns {Promise<void>}
   */
  async load() {
    if (this.loadedValue || this.loading) return;
    this.loading = true;

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": csrfToken,
        },
        credentials: "same-origin",
      });

      if (response.ok) {
        const html = await response.text();
        if (this.hasFrameTarget) {
          this.frameTarget.innerHTML = html;
        }
        if (this.hasLoadingTarget) {
          this.loadingTarget.classList.add("hidden");
        }
        this.loadedValue = true;
      } else {
        console.error("Lazy load failed:", response.status, response.statusText);
        this.showError(`Failed to load (${response.status})`);
      }
    } catch (error) {
      console.error("Lazy load error:", error);
      this.showError("Network error");
    } finally {
      this.loading = false;
    }
  }

  /**
   * Display an error message in the loading target
   * @param {string} message - The error message to display
   * @returns {void}
   */
  showError(message) {
    if (this.hasLoadingTarget) {
      this.loadingTarget.innerHTML = `<p class="text-destructive text-sm">${message}</p>`;
    }
  }
}
