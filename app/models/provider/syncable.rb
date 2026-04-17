# Module for providers that support syncing with external services
# Include this module in your adapter if the provider supports sync operations
module Provider::Syncable
  extend ActiveSupport::Concern

  # Returns the path to sync this provider's item
  # @return [String] The sync path
  def sync_path
    raise NotImplementedError, "#{self.class} must implement #sync_path"
  end

  def item
    raise NotImplementedError, "#{self.class} must implement #item"
  end

  def syncing?
    item&.syncing? || false
  end

  # Returns the current sync status
  # @return [String, nil] The status string or nil
  def status
    item&.status
  end

  def requires_update?
    status == "requires_update"
  end
end
