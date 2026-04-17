import ExchangeRateFormController from "controllers/exchange_rate_form_controller";

/**
 * @typedef {Object} TransactionExchangeRateContext
 * @property {string} fromCurrency - The transaction currency
 * @property {string} toCurrency - The account currency
 * @property {string} date - The transaction date
 */

/**
 * Connects to data-controller="transaction-form"
 * Extends ExchangeRateFormController for transaction-specific exchange rate handling
 */
export default class extends ExchangeRateFormController {
  /** @type {string[]} */
  static targets = [
    ...ExchangeRateFormController.targets,
    "account",
    "currency"
  ];

  /**
   * Check if all required targets for exchange rate functionality are present
   * @returns {boolean}
   */
  hasRequiredExchangeRateTargets() {
    if (!this.hasAccountTarget || !this.hasCurrencyTarget || !this.hasDateTarget) {
      return false;
    }

    return true;
  }

  /**
   * Get the exchange rate context from transaction form inputs
   * @returns {TransactionExchangeRateContext|null} The exchange rate context or null if not available
   */
  getExchangeRateContext() {
    if (!this.hasRequiredExchangeRateTargets()) {
      return null;
    }

    const accountId = this.accountTarget.value;
    const currency = this.currencyTarget.value;
    const date = this.dateTarget.value;

    if (!accountId || !currency) {
      return null;
    }

    const accountCurrency = this.accountCurrenciesValue[accountId];
    if (!accountCurrency) {
      return null;
    }

    return {
      fromCurrency: currency,
      toCurrency: accountCurrency,
      date
    };
  }

  /**
   * Check if the current exchange rate state matches the given parameters
   * @param {string} fromCurrency - The source currency to check
   * @param {string} toCurrency - The target currency to check
   * @param {string} date - The date to check
   * @returns {boolean}
   */
  isCurrentExchangeRateState(fromCurrency, toCurrency, date) {
    if (!this.hasRequiredExchangeRateTargets()) {
      return false;
    }

    const currentAccountId = this.accountTarget.value;
    const currentCurrency = this.currencyTarget.value;
    const currentDate = this.dateTarget.value;
    const currentAccountCurrency = this.accountCurrenciesValue[currentAccountId];

    return fromCurrency === currentCurrency && toCurrency === currentAccountCurrency && date === currentDate;
  }

  /**
   * Handle currency change events
   * @returns {void}
   */
  onCurrencyChange() {
    this.checkCurrencyDifference();
  }
}
