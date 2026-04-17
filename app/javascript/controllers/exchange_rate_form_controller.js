import { Controller } from "@hotwired/stimulus";

/**
 * @typedef {Object} ExchangeRateContext
 * @property {string} fromCurrency - Source currency code (e.g., "USD")
 * @property {string} toCurrency - Target currency code (e.g., "EUR")
 * @property {string} date - Date for the exchange rate in YYYY-MM-DD format
 */

/**
 * @typedef {Object} ExchangeRateResponse
 * @property {boolean} [same_currency] - Whether source and target currencies are the same
 * @property {number} [rate] - The exchange rate value
 * @property {string} [error] - Error message if the request failed
 */

/**
 * Base controller for exchange rate form functionality.
 * Handles currency conversion calculations and exchange rate fetching.
 * Subclasses must implement getExchangeRateContext() and isCurrentExchangeRateState().
 * @extends Controller
 */
export default class extends Controller {
  /**
   * Stimulus targets defined for this controller
   * @static
   * @type {string[]}
   */
  static targets = [
    "amount",
    "destinationAmount",
    "date",
    "exchangeRateContainer",
    "exchangeRateField",
    "convertDestinationDisplay",
    "calculateRateDisplay"
  ];

  /**
   * Stimulus values defined for this controller
   * @static
   * @type {Object}
   */
  static values = {
    exchangeRateUrl: String,
    accountCurrencies: Object
  };

  /**
   * Initialize the controller state and check for currency differences
   * @returns {void}
   */
  connect() {
    /** @type {string|null} */
    this.sourceCurrency = null;
    /** @type {string|null} */
    this.destinationCurrency = null;
    /** @type {string} */
    this.activeTab = "convert";

    if (!this.hasRequiredExchangeRateTargets()) {
      return;
    }

    this.checkCurrencyDifference();
  }

  /**
   * Check if all required targets for exchange rate functionality are present
   * @returns {boolean}
   */
  hasRequiredExchangeRateTargets() {
    return this.hasDateTarget;
  }

  /**
   * Check if currencies differ and fetch exchange rate if needed
   * @returns {void}
   */
  checkCurrencyDifference() {
    const context = this.getExchangeRateContext();

    if (!context) {
      this.hideExchangeRateField();
      return;
    }

    const { fromCurrency, toCurrency, date } = context;

    if (!fromCurrency || !toCurrency) {
      this.hideExchangeRateField();
      return;
    }

    this.sourceCurrency = fromCurrency;
    this.destinationCurrency = toCurrency;

    if (fromCurrency === toCurrency) {
      this.hideExchangeRateField();
      return;
    }

    this.fetchExchangeRate(fromCurrency, toCurrency, date);
  }

  /**
   * Handle clicks on exchange rate tab buttons
   * @param {MouseEvent} event - The click event
   * @returns {void}
   */
  onExchangeRateTabClick(event) {
    const btn = event.target.closest("button[data-id]");
    if (!btn) {
      return;
    }

    const nextTab = btn.dataset.id;

    if (nextTab === this.activeTab) {
      return;
    }

    this.activeTab = nextTab;

    if (this.activeTab === "convert") {
      this.clearCalculateRateFields();
    } else if (this.activeTab === "calculateRate") {
      this.clearConvertFields();
    }
  }

  /**
   * Handle amount input changes (legacy handler)
   * @returns {void}
   */
  onAmountChange() {
    this.onAmountInputChange();
  }

  /**
   * Handle source amount input changes (legacy handler)
   * @returns {void}
   */
  onSourceAmountChange() {
    this.onAmountInputChange();
  }

  /**
   * Handle amount input changes and trigger appropriate calculation
   * @returns {void}
   */
  onAmountInputChange() {
    if (!this.hasAmountTarget) {
      return;
    }

    if (this.activeTab === "convert") {
      this.calculateConvertDestination();
    } else {
      this.calculateRateFromAmounts();
    }
  }

  /**
   * Handle changes to the convert source amount input
   * @returns {void}
   */
  onConvertSourceAmountChange() {
    this.calculateConvertDestination();
  }

  /**
   * Handle changes to the exchange rate input
   * @returns {void}
   */
  onConvertExchangeRateChange() {
    this.calculateConvertDestination();
  }

  /**
   * Calculate destination amount based on source amount and exchange rate
   * @returns {void}
   */
  calculateConvertDestination() {
    if (!this.hasAmountTarget || !this.hasExchangeRateFieldTarget || !this.hasConvertDestinationDisplayTarget) {
      return;
    }

    const amount = Number.parseFloat(this.amountTarget.value);
    const rate = Number.parseFloat(this.exchangeRateFieldTarget.value);

    if (amount && rate && rate !== 0) {
      const destAmount = (amount * rate).toFixed(2);
      this.convertDestinationDisplayTarget.textContent = this.destinationCurrency ? `${destAmount} ${this.destinationCurrency}` : destAmount;
    } else {
      this.convertDestinationDisplayTarget.textContent = "-";
    }
  }

  /**
   * Handle changes to calculate rate source amount
   * @returns {void}
   */
  onCalculateRateSourceAmountChange() {
    this.calculateRateFromAmounts();
  }

  /**
   * Handle changes to calculate rate destination amount
   * @returns {void}
   */
  onCalculateRateDestinationAmountChange() {
    this.calculateRateFromAmounts();
  }

  /**
   * Calculate exchange rate from source and destination amounts
   * @returns {void}
   */
  calculateRateFromAmounts() {
    if (!this.hasAmountTarget || !this.hasDestinationAmountTarget || !this.hasCalculateRateDisplayTarget || !this.hasExchangeRateFieldTarget) {
      return;
    }

    const amount = Number.parseFloat(this.amountTarget.value);
    const destAmount = Number.parseFloat(this.destinationAmountTarget.value);

    if (amount && destAmount && amount !== 0) {
      const rate = destAmount / amount;
      const formattedRate = this.formatExchangeRate(rate);
      this.calculateRateDisplayTarget.textContent = formattedRate;
      this.exchangeRateFieldTarget.value = rate.toFixed(14);
    } else {
      this.calculateRateDisplayTarget.textContent = "-";
      this.exchangeRateFieldTarget.value = "";
    }
  }

  /**
   * Format an exchange rate value for display with appropriate precision
   * @param {number} rate - The exchange rate value to format
   * @returns {string} The formatted exchange rate string
   */
  formatExchangeRate(rate) {
    let formattedRate = rate.toFixed(14);
    formattedRate = formattedRate.replace(/(\.\d{2}\d*?)0+$/, "$1");

    if (!formattedRate.includes(".")) {
      formattedRate += ".00";
    } else if (formattedRate.match(/\.\d$/)) {
      formattedRate += "0";
    }

    return formattedRate;
  }

  /**
   * Clear all fields related to the convert tab
   * @returns {void}
   */
  clearConvertFields() {
    if (this.hasExchangeRateFieldTarget) {
      this.exchangeRateFieldTarget.value = "";
    }
    if (this.hasConvertDestinationDisplayTarget) {
      this.convertDestinationDisplayTarget.textContent = "-";
    }
  }

  /**
   * Clear all fields related to the calculate rate tab
   * @returns {void}
   */
  clearCalculateRateFields() {
    if (this.hasDestinationAmountTarget) {
      this.destinationAmountTarget.value = "";
    }
    if (this.hasCalculateRateDisplayTarget) {
      this.calculateRateDisplayTarget.textContent = "-";
    }
    if (this.hasExchangeRateFieldTarget) {
      this.exchangeRateFieldTarget.value = "";
    }
  }

  /**
   * Fetches exchange rate from the server
   * @param {string} fromCurrency - Source currency code (e.g., "USD")
   * @param {string} toCurrency - Target currency code (e.g., "EUR")
   * @param {string} [date] - Optional date for historical rates in YYYY-MM-DD format
   * @returns {Promise<void>}
   */
  async fetchExchangeRate(fromCurrency, toCurrency, date) {
    if (this.exchangeRateAbortController) {
      this.exchangeRateAbortController.abort();
    }

    this.exchangeRateAbortController = new AbortController();
    const signal = this.exchangeRateAbortController.signal;

    try {
      const url = new URL(this.exchangeRateUrlValue, window.location.origin);
      url.searchParams.set("from", fromCurrency);
      url.searchParams.set("to", toCurrency);
      if (date) {
        url.searchParams.set("date", date);
      }

      const response = await fetch(url, { signal });
      /** @type {ExchangeRateResponse} */
      const data = await response.json();

      if (!this.isCurrentExchangeRateState(fromCurrency, toCurrency, date)) {
        return;
      }

      if (!response.ok) {
        if (this.shouldShowManualExchangeRate(data)) {
          this.showManualExchangeRateField();
        } else {
          this.hideExchangeRateField();
        }
        return;
      }

      if (data.same_currency) {
        this.hideExchangeRateField();
      } else {
        this.sourceCurrency = fromCurrency;
        this.destinationCurrency = toCurrency;
        this.showExchangeRateField(data.rate);
      }
    } catch (error) {
      if (error.name === "AbortError") {
        return;
      }

      console.error("Error fetching exchange rate:", error);
      this.hideExchangeRateField();
    }
  }

  /**
   * Display the exchange rate field with the fetched rate
   * @param {number} rate - The exchange rate to display
   * @returns {void}
   */
  showExchangeRateField(rate) {
    if (this.hasExchangeRateFieldTarget) {
      this.exchangeRateFieldTarget.value = this.formatExchangeRate(rate);
    }
    if (this.hasExchangeRateContainerTarget) {
      this.exchangeRateContainerTarget.classList.remove("hidden");
    }

    this.calculateConvertDestination();
  }

  /**
   * Display manual exchange rate input field for user entry
   * @returns {void}
   */
  showManualExchangeRateField() {
    const context = this.getExchangeRateContext();
    this.sourceCurrency = context?.fromCurrency || null;
    this.destinationCurrency = context?.toCurrency || null;

    if (this.hasExchangeRateFieldTarget) {
      this.exchangeRateFieldTarget.value = "";
    }
    if (this.hasExchangeRateContainerTarget) {
      this.exchangeRateContainerTarget.classList.remove("hidden");
    }

    this.calculateConvertDestination();
  }

  /**
   * Determine if manual exchange rate input should be shown based on error response
   * @param {ExchangeRateResponse} data - The error response data
   * @returns {boolean}
   */
  shouldShowManualExchangeRate(data) {
    if (!data || typeof data.error !== "string") {
      return false;
    }

    return data.error === "Exchange rate not found" || data.error === "Exchange rate unavailable";
  }

  /**
   * Hide the exchange rate field and reset related state
   * @returns {void}
   */
  hideExchangeRateField() {
    if (this.hasExchangeRateContainerTarget) {
      this.exchangeRateContainerTarget.classList.add("hidden");
    }
    if (this.hasExchangeRateFieldTarget) {
      this.exchangeRateFieldTarget.value = "";
    }
    if (this.hasConvertDestinationDisplayTarget) {
      this.convertDestinationDisplayTarget.textContent = "-";
    }
    if (this.hasCalculateRateDisplayTarget) {
      this.calculateRateDisplayTarget.textContent = "-";
    }
    if (this.hasDestinationAmountTarget) {
      this.destinationAmountTarget.value = "";
    }

    this.sourceCurrency = null;
    this.destinationCurrency = null;
  }

  /**
   * Get the exchange rate context from subclass implementation
   * @abstract
   * @returns {ExchangeRateContext|null} The context object containing fromCurrency, toCurrency, and date
   * @throws {Error} Always throws - subclasses must implement this method
   */
  getExchangeRateContext() {
    throw new Error("Subclasses must implement getExchangeRateContext()");
  }

  /**
   * Check if the current exchange rate state matches the request parameters
   * @abstract
   * @param {string} _fromCurrency - Source currency code
   * @param {string} _toCurrency - Target currency code
   * @param {string} [_date] - Optional date for historical rates
   * @returns {boolean} Whether the state matches
   * @throws {Error} Always throws - subclasses must implement this method
   */
  isCurrentExchangeRateState(_fromCurrency, _toCurrency, _date) {
    throw new Error("Subclasses must implement isCurrentExchangeRateState()");
  }
}
