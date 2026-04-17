class InstrumentMappingsController < ApplicationController
  before_action :require_admin!
  before_action :set_instrument_mapping, only: [:update]

  def index
    @filter = params[:filter] || "pending"
    @sleeves = current_sleeves
    @instrument_mappings = fetch_instrument_mappings
    @holdings = fetch_holdings_with_mappings
  end

  def create
    @holding = Holding.find(params[:holding_id])
    @instrument_mapping = InstrumentMapping.new(
      holding: @holding,
      mapped_status: params[:action_type] == "exclude" ? :excluded : :pending
    )

    if @instrument_mapping.save
      respond_to do |format|
        format.html { redirect_to instrument_mappings_path(filter: params[:filter]), notice: t(".success") }
        format.json { head :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to instrument_mappings_path, alert: @instrument_mapping.errors.full_messages.join(", ") }
        format.json { render json: @instrument_mapping.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    case params[:action_type]
    when "approve"
      approve_mapping
    when "exclude"
      exclude_mapping
    when "reset"
      reset_mapping
    else
      head :bad_request
      return
    end

    respond_to do |format|
      format.html { redirect_to instrument_mappings_path(filter: params[:filter]), notice: t(".success") }
      format.json { head :ok }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@instrument_mapping) }
    end
  end

  def bulk_approve
    holding_ids = params[:holding_ids] || []
    sleeve_id = params[:sleeve_id]

    if sleeve_id.blank?
      redirect_to instrument_mappings_path, alert: t(".sleeve_required")
      return
    end

    approved_count = 0
    holding_ids.each do |holding_id|
      mapping = InstrumentMapping.find_or_initialize_by(holding_id: holding_id)
      mapping.sleeve_id = sleeve_id
      mapping.mapped_status = :approved
      mapping.mapping_confidence = :high
      mapping.user_approved_at = Time.current
      if mapping.save
        approved_count += 1
      end
    end

    redirect_to instrument_mappings_path(filter: params[:filter]),
                notice: t(".bulk_approved", count: approved_count)
  end

  def bulk_exclude
    holding_ids = params[:holding_ids] || []

    excluded_count = 0
    holding_ids.each do |holding_id|
      mapping = InstrumentMapping.find_or_initialize_by(holding_id: holding_id)
      mapping.mapped_status = :excluded
      if mapping.save
        excluded_count += 1
      end
    end

    redirect_to instrument_mappings_path(filter: params[:filter]),
                notice: t(".bulk_excluded", count: excluded_count)
  end

  private

    def set_instrument_mapping
      @instrument_mapping = InstrumentMapping.find(params[:id])
    end

    def fetch_instrument_mappings
      scope = InstrumentMapping.joins(:holding).where(holdings: { account_id: Current.family.account_ids })

      case @filter
      when "pending"
        scope.pending
      when "approved"
        scope.approved
      when "excluded"
        scope.excluded
      else
        scope
      end
    end

    def fetch_holdings_with_mappings
      holdings = Current.family.holdings
        .includes(:security, :account, :instrument_mapping)
        .where.not(qty: 0)

      case @filter
      when "pending"
        holdings = holdings.left_joins(:instrument_mapping)
                           .where(instrument_mappings: { id: nil })
                           .or(holdings.left_joins(:instrument_mapping)
                                       .where(instrument_mappings: { mapped_status: :pending }))
      when "approved"
        holdings = holdings.joins(:instrument_mapping)
                           .where(instrument_mappings: { mapped_status: :approved })
      when "excluded"
        holdings = holdings.joins(:instrument_mapping)
                           .where(instrument_mappings: { mapped_status: :excluded })
      end

      holdings.order("securities.name ASC")
    end

    def current_sleeves
      return [] unless Current.family.respond_to?(:policy_versions)

      current_policy = Current.family.policy_versions.active.first
      return [] unless current_policy

      current_policy.sleeves.ordered
    end

    def approve_mapping
      sleeve_id = params[:sleeve_id]

      if sleeve_id.present?
        @instrument_mapping.sleeve_id = sleeve_id
      end

      @instrument_mapping.approve!
    end

    def exclude_mapping
      @instrument_mapping.exclude!
    end

    def reset_mapping
      @instrument_mapping.reset!
    end
end
