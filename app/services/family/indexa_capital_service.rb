# Manages Indexa Capital connections for a Family.
# Extracted from IndexaCapitalConnectable concern to respect Single Responsibility Principle.
class Family::IndexaCapitalService < Family::ProviderService
  def self.item_association_name
    :indexa_capital_items
  end

  def self.item_class
    IndexaCapitalItem
  end

  # Families can configure their own IndexaCapital credentials
  def can_connect?
    true
  end

  def create_item!(username:, document:, password:, item_name: nil)
    indexa_capital_item = family.indexa_capital_items.create!(
      name: item_name || "Indexa Capital Connection",
      username: username,
      document: document,
      password: password
    )

    indexa_capital_item.sync_later

    indexa_capital_item
  end

  def has_credentials?
    family.indexa_capital_items.where.not(api_token: [ nil, "" ]).or(
      family.indexa_capital_items.where.not(username: [ nil, "" ])
                          .where.not(document: [ nil, "" ])
                          .where.not(password: [ nil, "" ])
    ).exists?
  end
end
