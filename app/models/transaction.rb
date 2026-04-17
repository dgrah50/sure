class Transaction < ApplicationRecord
  include Entryable, Splittable

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  # File attachments (receipts, invoices, etc.) using Active Storage
  # Supports images (JPEG, PNG, GIF, WebP) and PDFs up to 10MB each
  # Maximum 10 attachments per transaction, family-scoped access
  has_many_attached :attachments do |attachable|
    attachable.variant :thumbnail, resize_to_limit: [ 150, 150 ]
  end

  # Attachment validation constants
  MAX_ATTACHMENTS_PER_TRANSACTION = 10
  MAX_ATTACHMENT_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/jpg image/png image/gif image/webp
    application/pdf
  ].freeze

  validate :validate_attachments, if: -> { attachments.attached? }

  accepts_nested_attributes_for :taggings, allow_destroy: true

  # Accessors for exchange_rate stored in extra jsonb field
  def exchange_rate
    extra&.dig("exchange_rate")
  end

  def exchange_rate=(value)
    if value.blank?
      self.extra = (extra || {}).merge("exchange_rate" => nil)
    else
      begin
        normalized_value = Float(value)
        self.extra = (extra || {}).merge("exchange_rate" => normalized_value)
      rescue ArgumentError, TypeError
        # Store the raw value for validation error reporting
        self.extra = (extra || {}).merge("exchange_rate" => value, "exchange_rate_invalid" => true)
      end
    end
  end

  validate :exchange_rate_must_be_valid

  private

    def exchange_rate_must_be_valid
      if extra&.dig("exchange_rate_invalid")
        errors.add(:exchange_rate, "must be a number")
      elsif exchange_rate.present?
        # Convert to float for comparison
        numeric_rate = exchange_rate.to_d rescue nil
        if numeric_rate.nil? || numeric_rate <= 0
          errors.add(:exchange_rate, "must be greater than 0")
        end
      end
    end

  public

  enum :kind, {
    standard: "standard" # A regular transaction
  }

  # Providers that support pending transaction flags
  PENDING_PROVIDERS = %w[simplefin plaid lunchflow enable_banking].freeze

  # Pending transaction scopes - filter based on provider pending flags in extra JSONB
  # Works with any provider that stores pending status in extra["provider_name"]["pending"]
  scope :pending, -> {
    conditions = PENDING_PROVIDERS.map { |provider| "(transactions.extra -> '#{provider}' ->> 'pending')::boolean = true" }
    where(conditions.join(" OR "))
  }

  scope :excluding_pending, -> {
    conditions = PENDING_PROVIDERS.map { |provider| "(transactions.extra -> '#{provider}' ->> 'pending')::boolean IS DISTINCT FROM true" }
    where(conditions.join(" AND "))
  }

  # SQL snippet for raw queries that must exclude pending transactions.
  # Use in income statements, balance sheets, and raw analytics.
  def self.pending_providers_sql(table_alias = "t")
    PENDING_PROVIDERS.map do |provider|
      "AND (#{table_alias}.extra -> '#{provider}' ->> 'pending')::boolean IS DISTINCT FROM true"
    end.join("\n")
  end

  # Family-scoped query for Enrichable#clear_ai_cache
  def self.family_scope(family)
    joins(entry: :account).where(accounts: { family_id: family.id })
  end

  def pending?
    extra_data = extra.is_a?(Hash) ? extra : {}
    PENDING_PROVIDERS.any? do |provider|
      ActiveModel::Type::Boolean.new.cast(extra_data.dig(provider, "pending"))
    end
  rescue
    false
  end

  # Potential duplicate matching methods
  # These help users review and resolve fuzzy-matched pending/posted pairs

  def has_potential_duplicate?
    potential_posted_match_data.present? && !potential_duplicate_dismissed?
  end

  def potential_duplicate_entry
    return nil unless has_potential_duplicate?
    Entry.find_by(id: potential_posted_match_data["entry_id"])
  end

  def potential_duplicate_reason
    potential_posted_match_data&.dig("reason")
  end

  def potential_duplicate_confidence
    potential_posted_match_data&.dig("confidence") || "medium"
  end

  def low_confidence_duplicate?
    potential_duplicate_confidence == "low"
  end

  def potential_duplicate_posted_amount
    potential_posted_match_data&.dig("posted_amount")&.to_d
  end

  def potential_duplicate_dismissed?
    potential_posted_match_data&.dig("dismissed") == true
  end

  # Merge this pending transaction with its suggested posted match
  # This DELETES the pending entry since the posted version is canonical
  def merge_with_duplicate!
    return false unless has_potential_duplicate?

    posted_entry = potential_duplicate_entry
    return false unless posted_entry

    pending_entry_id = entry.id
    pending_entry_name = entry.name

    # Delete this pending entry completely (no need to keep it around)
    entry.destroy!

    Rails.logger.info("User merged pending entry #{pending_entry_id} (#{pending_entry_name}) with posted entry #{posted_entry.id}")
    true
  end

  # Dismiss the duplicate suggestion - user says these are NOT the same transaction
  def dismiss_duplicate_suggestion!
    return false unless potential_posted_match_data.present?

    updated_extra = (extra || {}).deep_dup
    updated_extra["potential_posted_match"]["dismissed"] = true
    update!(extra: updated_extra)

    Rails.logger.info("User dismissed duplicate suggestion for entry #{entry.id}")
    true
  end

  # Clear the duplicate suggestion entirely
  def clear_duplicate_suggestion!
    return false unless potential_posted_match_data.present?

    updated_extra = (extra || {}).deep_dup
    updated_extra.delete("potential_posted_match")
    update!(extra: updated_extra)
    true
  end

  # Find potential posted transactions that might be duplicates of this pending transaction
  # Returns entries (not transactions) for UI consistency with transfer matcher
  # Lists recent posted transactions from the same account for manual merging
  def pending_duplicate_candidates(limit: 20, offset: 0)
    return Entry.none unless pending? && entry.present?

    account = entry.account
    currency = entry.currency

    # Find recent posted transactions from the same account
    conditions = PENDING_PROVIDERS.map { |provider| "(transactions.extra -> '#{provider}' ->> 'pending')::boolean IS NOT TRUE" }

    account.entries
      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
      .where.not(id: entry.id)
      .where(currency: currency)
      .where(conditions.join(" AND "))
      .order(date: :desc, created_at: :desc)
      .limit(limit)
      .offset(offset)
  end

  private

    def validate_attachments
      # Check attachment count limit
      if attachments.size > MAX_ATTACHMENTS_PER_TRANSACTION
        errors.add(:attachments, :too_many, max: MAX_ATTACHMENTS_PER_TRANSACTION)
      end

      # Validate each attachment
      attachments.each_with_index do |attachment, index|
        # Check file size
        if attachment.byte_size > MAX_ATTACHMENT_SIZE
          errors.add(:attachments, :too_large, index: index + 1, max_mb: MAX_ATTACHMENT_SIZE / 1.megabyte)
        end

        # Check content type
        unless ALLOWED_CONTENT_TYPES.include?(attachment.content_type)
          errors.add(:attachments, :invalid_format, index: index + 1, file_format: attachment.content_type)
        end
      end
    end

    def potential_posted_match_data
      return nil unless extra.is_a?(Hash)
      extra["potential_posted_match"]
    end
end
