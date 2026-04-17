class ImportMarketDataJob < ApplicationJob
  queue_as :scheduled

  def perform(mode: "full", clear_cache: false)
    importer = MarketDataImporter.new(mode: mode, clear_cache: clear_cache)
    importer.import_all
  end
end
