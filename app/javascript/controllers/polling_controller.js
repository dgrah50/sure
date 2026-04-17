import { Controller } from "@hotwired/stimulus";

/**
 * Connects to data-controller="polling"
 * Automatically refreshes a turbo frame at a specified interval
 */
export default class extends Controller {
  /** @type {Object.<string, any>} */
  static values = {
    url: String,
    interval: { type: Number, default: 3000 },
  };

  /** @type {number|null} */
  poll = null;

  /**
   * Start polling when controller connects
   * @returns {void}
   */
  connect() {
    this.startPolling();
  }

  /**
   * Stop polling when controller disconnects
   * @returns {void}
   */
  disconnect() {
    this.stopPolling();
  }

  /**
   * Start the polling interval
   * @returns {void}
   */
  startPolling() {
    if (!this.hasUrlValue) return;

    this.poll = setInterval(() => {
      this.refresh();
    }, this.intervalValue);
  }

  /**
   * Stop the polling interval
   * @returns {void}
   */
  stopPolling() {
    if (this.poll) {
      clearInterval(this.poll);
      this.poll = null;
    }
  }

  /**
   * Fetch fresh content from the server and update the frame
   * @returns {Promise<void>}
   */
  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/html",
          "Turbo-Frame": this.element.id,
        },
      });

      if (response.ok) {
        const html = await response.text();
        const template = document.createElement("template");
        template.innerHTML = html;

        const newFrame = template.content.querySelector(
          `turbo-frame#${this.element.id}`,
        );
        if (newFrame) {
          this.element.innerHTML = newFrame.innerHTML;

          // Check if we should stop polling (no more pending/processing exports)
          if (!newFrame.hasAttribute("data-polling-url-value")) {
            this.stopPolling();
          }
        }
      }
    } catch (error) {
      console.error("Polling error:", error);
    }
  }
}
