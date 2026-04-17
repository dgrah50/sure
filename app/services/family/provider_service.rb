# Base class for family provider services.
# Provides a consistent interface for managing provider connections
# without cluttering the Family model with provider-specific logic.
#
# Subclasses should implement:
# - can_connect? - Boolean indicating if the family can connect to this provider
# - create_item! - Creates and returns a new provider item
class Family::ProviderService
  attr_reader :family

  def initialize(family)
    @family = family
  end

  # Returns the association name for this provider's items
  # e.g., :plaid_items, :simplefin_items
  def self.item_association_name
    raise NotImplementedError
  end

  # Returns the provider item class
  def self.item_class
    raise NotImplementedError
  end

  # Subclasses must implement this method
  def can_connect?
    raise NotImplementedError
  end

  private

    def items
      family.public_send(self.class.item_association_name)
    end
end
