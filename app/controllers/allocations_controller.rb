class AllocationsController < ApplicationController
  def show
    @policy = PolicyVersion.for_family(Current.family).active.first
    @sleeves = @policy&.sleeves&.root&.ordered || []
    @risk_assessment = RiskAssessmentService.new(Current.family).assess
    
    @total_value = total_portfolio_value
    @sleeve_allocations = build_sleeve_allocations
    @unmapped_holdings = fetch_unmapped_holdings
    
    @breadcrumbs = [ [ t(".nav.overview"), overview_path ], [ t(".title"), nil ] ]
  end

  private

    def total_portfolio_value
      Current.family.accounts
            .assets
            .where(status: "active")
            .sum(:balance)
            .to_d
    end

    def build_sleeve_allocations
      return [] if @total_value.zero?

      @sleeves.map do |sleeve|
        current_value = calculate_sleeve_value(sleeve)
        current_pct = (current_value / @total_value * 100).round(2)
        target_pct = sleeve.target_percentage.to_f
        dollar_gap = ((current_pct - target_pct) / 100 * @total_value).round(2)

        {
          sleeve: sleeve,
          target_pct: target_pct,
          current_pct: current_pct,
          current_value: current_value,
          dollar_gap: dollar_gap,
          status: allocation_status(current_pct, sleeve)
        }
      end
    end

    def calculate_sleeve_value(sleeve)
      # Get all holdings mapped to this sleeve
      security_ids = InstrumentMapping.where(sleeve_id: sleeve.id, status: "approved").pluck(:security_id)
      
      latest_holdings = Current.family.holdings
            .includes(:security)
            .where(currency: Current.family.currency)
            .where(security_id: security_ids)
            .where.not(qty: 0)
            .where(
              id: Current.family.holdings
                        .select("DISTINCT ON (security_id) id")
                        .where(currency: Current.family.currency)
                        .order(:security_id, date: :desc)
            )
      
      latest_holdings.sum(&:amount)
    end

    def allocation_status(current_pct, sleeve)
      min_pct = sleeve.effective_min_percentage
      max_pct = sleeve.effective_max_percentage

      if current_pct >= min_pct && current_pct <= max_pct
        :on_target
      elsif current_pct < min_pct
        :under_allocated
      else
        :over_allocated
      end
    end

    def fetch_unmapped_holdings
      mapped_security_ids = InstrumentMapping.approved.pluck(:security_id)
      
      Current.family.holdings
            .includes(:security)
            .where(currency: Current.family.currency)
            .where.not(security_id: mapped_security_ids)
            .where.not(qty: 0)
            .where(
              id: Current.family.holdings
                        .select("DISTINCT ON (security_id) id")
                        .where(currency: Current.family.currency)
                        .order(:security_id, date: :desc)
            )
    end

  helper_method :allocation_status_config

  def allocation_status_config(status)
    case status
    when :on_target
      { icon: "check-circle", class: "bg-success/10 text-success" }
    when :under_allocated
      { icon: "minus-circle", class: "bg-warning/10 text-warning" }
    when :over_allocated
      { icon: "alert-circle", class: "bg-destructive/10 text-destructive" }
    else
      { icon: "help-circle", class: "bg-secondary/10 text-secondary" }
    end
  end
end
