/**
 * @typedef {Object} Currency
 * @property {string} iso_code
 * @property {string} name
 * @property {string} symbol
 * @property {string} step
 * @property {number} default_precision
 */

/**
 * @typedef {Object} ExchangeRateResponse
 * @property {number} [rate]
 * @property {boolean} [same_currency]
 * @property {string} [error]
 */

/**
 * Service for fetching currency data from the server
 */
export class CurrenciesService {
  /**
   * Validates that the response contains required Currency fields
   * @param {*} data - Response data
   * @returns {boolean}
   */
  #isValidCurrencyResponse(data) {
    return data &&
      typeof data === 'object' &&
      typeof data.iso_code === 'string' &&
      typeof data.symbol === 'string' &&
      typeof data.step === 'string';
  }

  /**
   * Fetch currency data by ISO code
   * @param {string} id - The currency ISO code (e.g., 'USD', 'EUR')
   * @returns {Promise<Currency>} A promise resolving to the currency data
   */
  get(id) {
    return fetch(`/currencies/${id}.json`)
      .then((response) => response.json())
      .then((data) => {
        if (!this.#isValidCurrencyResponse(data)) {
          console.error('Invalid currency response:', data);
          throw new Error('Invalid currency response from server');
        }
        return data;
      });
  }
}
