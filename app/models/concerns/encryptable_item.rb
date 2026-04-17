module EncryptableItem
  extend ActiveSupport::Concern

  class_methods do
    def encryption_ready?
      creds_ready = Rails.application.credentials.active_record_encryption.present?
      env_ready = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present? &&
                  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].present? &&
                  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].present?
      creds_ready || env_ready
    end
  end
end
