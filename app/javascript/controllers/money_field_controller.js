import { Controller } from "@hotwired/stimulus";
import { CurrenciesService } from "services/currencies_service";
import parseLocaleFloat from "utils/parse_locale_float";

/**
 * @typedef {Object} Currency
 * @property {string} iso_code
 * @property {string} name
 * @property {string} symbol
 * @property {string} step
 * @property {number} default_precision
 */

/**
 * Connects to data-controller="money-field"
 * When currency select changes, update the input value with the correct placeholder and step
 */
export default class extends Controller {
  /** @type {string[]} */
  static targets = ["amount", "currency", "symbol"];

  /** @type {Object.<string, any>} */
  static values = {
    precision: Number,
    step: String,
  };

  /** @type {number} */
  requestSequence = 0;

  /**
   * Handle currency selection change event
   * @param {Event} e - The change event from the currency select element
   * @returns {void}
   */
  handleCurrencyChange(e) {
    const selectedCurrency = e.target.value;
    this.updateAmount(selectedCurrency);
  }

  /**
   * Update the amount input based on the selected currency
   * @param {string} currency - The ISO code of the selected currency
   * @returns {void}
   */
  updateAmount(currency) {
    const requestId = ++this.requestSequence;
    new CurrenciesService().get(currency).then((currencyData) => {
      if (requestId !== this.requestSequence) return;

      this.amountTarget.step =
        this.hasStepValue &&
        this.stepValue !== "" &&
        (this.stepValue === "any" || Number.isFinite(Number(this.stepValue)))
          ? this.stepValue
          : currencyData.step;

      const rawValue = this.amountTarget.value.trim();
      if (rawValue !== "") {
        const parsedAmount = parseLocaleFloat(rawValue);
        if (Number.isFinite(parsedAmount)) {
          const precision =
            this.hasPrecisionValue && Number.isInteger(this.precisionValue)
              ? this.precisionValue
              : currencyData.default_precision;
          this.amountTarget.value = parsedAmount.toFixed(precision);
        }
      }

      this.symbolTarget.innerText = currencyData.symbol;
    }).catch(() => {
      // Catch prevents Unhandled Promise Rejection for network failures.
      // Silently ignored as they are unactionable by the user.
    });
  }
}
