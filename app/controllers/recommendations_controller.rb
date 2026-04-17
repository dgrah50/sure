class RecommendationsController < ApplicationController
  before_action :set_recommendation, only: %i[show approve reject dismiss complete]
  before_action :require_recommendation_permission!, only: %i[approve reject dismiss complete]

  def index
    @recommendations = Current.family.recommendations.ordered
    @grouped_recommendations = group_recommendations(@recommendations)
  end

  def show
    @decision_logs = DecisionLog.for_reference(@recommendation).recent
  end

  def approve
    if @recommendation.approve!(Current.user)
      DecisionLog.log_decision(
        family: Current.family,
        actor: Current.user,
        decision_type: "recommendation_approved",
        reference: @recommendation,
        rationale: params[:rationale].presence || t(".default_rationale")
      )
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    respond_to do |format|
      format.html { redirect_to recommendation_path(@recommendation) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@recommendation) }
    end
  end

  def reject
    if @recommendation.reject!(Current.user)
      DecisionLog.log_decision(
        family: Current.family,
        actor: Current.user,
        decision_type: "recommendation_rejected",
        reference: @recommendation,
        rationale: params[:rationale].presence || t(".default_rationale")
      )
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    respond_to do |format|
      format.html { redirect_to recommendation_path(@recommendation) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@recommendation) }
    end
  end

  def dismiss
    if @recommendation.pending? && params[:rationale].present?
      DecisionLog.log_decision(
        family: Current.family,
        actor: Current.user,
        decision_type: "action_dismissed",
        reference: @recommendation,
        rationale: params[:rationale]
      )
    end

    flash[:notice] = t(".success")

    respond_to do |format|
      format.html { redirect_to recommendations_path }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@recommendation) }
    end
  end

  def complete
    if @recommendation.approved? && @recommendation.execute!
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    respond_to do |format|
      format.html { redirect_to recommendation_path(@recommendation) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@recommendation) }
    end
  end

  private
    def set_recommendation
      @recommendation = Current.family.recommendations.find(params[:id])
    end

    def require_recommendation_permission!
      return if Current.user.present?

      respond_to do |format|
        format.html { redirect_to recommendations_path, alert: t("shared.require_user") }
        format.turbo_stream { head :forbidden }
      end
      false
    end

    def group_recommendations(recommendations)
      today = Date.current
      this_week = today.beginning_of_week..today.end_of_week
      this_month = today.beginning_of_month..today.end_of_month

      {
        today: recommendations.select { |r| r.created_at.to_date == today && r.pending? },
        this_week: recommendations.select { |r| this_week.cover?(r.created_at.to_date) && r.pending? && r.created_at.to_date != today },
        this_month: recommendations.select { |r| this_month.cover?(r.created_at.to_date) && r.pending? && !this_week.cover?(r.created_at.to_date) },
        future: recommendations.select { |r| r.pending? && r.created_at.to_date > today.end_of_month },
        completed: recommendations.reject(&:pending?)
      }
    end
end
