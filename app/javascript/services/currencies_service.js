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
