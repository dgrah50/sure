/**
 * @fileoverview Shared type definitions for the Sure application
 * @description This file contains JSDoc type definitions used across the codebase.
 * These types are for documentation purposes only and are not enforced at runtime.
 */

/**
 * @typedef {Object} Currency
 * @property {string} iso_code - ISO 4217 currency code
 * @property {string} name - Full currency name
 * @property {string} symbol - Currency symbol (e.g., "$", "€")
 * @property {string} step - Minimum step value for inputs
 * @property {number} default_precision - Default decimal places
 */

/**
 * @typedef {Object} MoneyAmount
 * @property {number} cents - Amount in cents/smallest unit
 * @property {string} currency - ISO currency code
 * @property {string} [formatted] - Pre-formatted display string
 */

/**
 * @typedef {Object} ExchangeRateResponse
 * @property {number} [rate] - Exchange rate value
 * @property {boolean} [same_currency] - True if from === to currency
 * @property {string} [error] - Error message if request failed
 */

/**
 * @typedef {Object} ApiError
 * @property {string} error - Error code
 * @property {string} message - Human-readable error message
 */

/**
 * @typedef {Object} TimeSeriesPoint
 * @property {string} date - ISO date string (YYYY-MM-DD)
 * @property {string} date_formatted - Human-readable date
 * @property {MoneyAmount|number} value - The data point value
 * @property {Trend} trend - Trend information
 */

/**
 * @typedef {Object} Trend
 * @property {string} color - Color for trend display
 * @property {MoneyAmount} current - Current period value
 * @property {MoneyAmount} previous - Previous period value
 * @property {number} value - Raw trend value
 * @property {string} percent_formatted - Formatted percentage
 */

/**
 * @typedef {Object} DonutSegment
 * @property {string} id - Segment identifier
 * @property {number} amount - Numeric amount for the segment
 * @property {string} color - CSS color value
 * @property {string} [name] - Display name
 */

/**
 * @typedef {Object} SankeyNode
 * @property {string} id - Node identifier
 * @property {string} name - Display name
 * @property {string} [color] - CSS color value
 * @property {number} [value] - Node value
 */

/**
 * @typedef {Object} SankeyLink
 * @property {string|number} source - Source node reference
 * @property {string|number} target - Target node reference
 * @property {number} value - Link value
 * @property {string} [percentage] - Formatted percentage
 */

/**
 * @typedef {Object} LunchflowPreloadResponse
 * @property {boolean} success - Whether the request succeeded
 * @property {boolean} has_accounts - Whether accounts are available
 * @property {boolean} [cached] - Whether data came from cache
 * @property {string} [error] - Error code if failed
 * @property {string} [error_message] - Human-readable error
 */
