class DataSourcesController < ApplicationController
  before_action :require_admin!

  def show
    @provider_groups = gather_provider_groups
    @health_statuses = Current.family.data_health_statuses
    @data_quality_summary = Current.family.data_quality_summary || DataQualitySummary.refresh!(Current.family)
  end

  def sync_all
    sync_counts = {
      plaid: 0,
      simplefin: 0,
      coinbase: 0,
      binance: 0,
      coinstats: 0,
      snaptrade: 0,
      mercury: 0,
      indexa_capital: 0,
      lunchflow: 0,
      enable_banking: 0
    }

    Current.family.plaid_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:plaid] += 1
    end

    Current.family.simplefin_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:simplefin] += 1
    end

    Current.family.coinbase_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:coinbase] += 1
    end

    Current.family.binance_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:binance] += 1
    end

    Current.family.coinstats_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:coinstats] += 1
    end

    Current.family.snaptrade_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:snaptrade] += 1
    end

    Current.family.mercury_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:mercury] += 1
    end

    Current.family.indexa_capital_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:indexa_capital] += 1
    end

    Current.family.lunchflow_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:lunchflow] += 1
    end

    Current.family.enable_banking_items.active.syncable.each do |item|
      item.sync_later unless item.syncing?
      sync_counts[:enable_banking] += 1
    end

    total_synced = sync_counts.values.sum

    if total_synced > 0
      notice = t(".success", count: total_synced)
    else
      notice = t(".no_sync_needed")
    end

    respond_to do |format|
      format.html { redirect_to data_sources_path, notice: notice }
      format.json { render json: { synced: total_synced, breakdown: sync_counts } }
    end
  end

  def disconnect
    health_status = Current.family.data_health_statuses.find(params[:id])
    provider = health_status.provider

    if provider
      provider.destroy_later if provider.respond_to?(:destroy_later)
      provider.destroy if provider.respond_to?(:destroy) && !provider.respond_to?(:destroy_later)
    end

    health_status.update!(connection_state: :disconnected)

    respond_to do |format|
      format.html { redirect_to data_sources_path, notice: t(".success") }
      format.json { head :ok }
    end
  end

  private

    def gather_provider_groups
      groups = {}

      plaid_items = Current.family.plaid_items.active.ordered
      groups[:plaid] = plaid_items if plaid_items.any?

      simplefin_items = Current.family.simplefin_items.active.ordered
      groups[:simplefin] = simplefin_items if simplefin_items.any?

      coinbase_items = Current.family.coinbase_items.active.ordered
      groups[:coinbase] = coinbase_items if coinbase_items.any?

      binance_items = Current.family.binance_items.active.ordered
      groups[:binance] = binance_items if binance_items.any?

      coinstats_items = Current.family.coinstats_items.active.ordered
      groups[:coinstats] = coinstats_items if coinstats_items.any?

      snaptrade_items = Current.family.snaptrade_items.active.ordered
      groups[:snaptrade] = snaptrade_items if snaptrade_items.any?

      mercury_items = Current.family.mercury_items.active.ordered
      groups[:mercury] = mercury_items if mercury_items.any?

      indexa_capital_items = Current.family.indexa_capital_items.active.ordered
      groups[:indexa_capital] = indexa_capital_items if indexa_capital_items.any?

      lunchflow_items = Current.family.lunchflow_items.active.ordered
      groups[:lunchflow] = lunchflow_items if lunchflow_items.any?

      enable_banking_items = Current.family.enable_banking_items.active.ordered
      groups[:enable_banking] = enable_banking_items if enable_banking_items.any?

      groups
    end
end
