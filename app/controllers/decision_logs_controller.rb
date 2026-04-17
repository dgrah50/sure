class DecisionLogsController < ApplicationController
  before_action :set_decision_log, only: :show

  def index
    @decision_logs = Current.family.decision_logs.recent

    if params[:decision_type].present? && DecisionLog::DECISION_TYPES.include?(params[:decision_type])
      @decision_logs = @decision_logs.by_type(params[:decision_type])
    end

    if params[:since].present?
      @decision_logs = @decision_logs.since(params[:since].to_date)
    end

    @pagy, @decision_logs = pagy(@decision_logs, items: params[:per_page] || 25)
  end

  def show
    @reference = @decision_log.reference
  end

  private
    def set_decision_log
      @decision_log = Current.family.decision_logs.find(params[:id])
    end
end
