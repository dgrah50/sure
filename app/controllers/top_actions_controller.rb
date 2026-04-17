class TopActionsController < ApplicationController
  before_action :set_top_action, only: %i[show dismiss complete refresh]
  before_action :require_top_action_permission!, only: %i[dismiss complete refresh]

  def show
    @top_action = Current.family.top_actions.active.ordered.first

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def dismiss
    if @top_action.dismiss!
      DecisionLog.log_decision(
        family: Current.family,
        actor: Current.user,
        decision_type: "action_dismissed",
        reference: @top_action,
        rationale: params[:rationale].presence || t(".default_rationale")
      )
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    respond_to do |format|
      format.html { redirect_back_or_to root_path }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@top_action),
          turbo_stream.replace("top_action_widget", partial: "top_actions/widget")
        ]
      end
    end
  end

  def complete
    if @top_action.complete!
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    respond_to do |format|
      format.html { redirect_back_or_to root_path }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@top_action),
          turbo_stream.replace("top_action_widget", partial: "top_actions/widget")
        ]
      end
    end
  end

  def refresh
    @top_action = Current.family.top_actions.active.ordered.first

    respond_to do |format|
      format.html { redirect_back_or_to root_path }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("top_action_widget", partial: "top_actions/widget", locals: { top_action: @top_action })
      end
    end
  end

  private
    def set_top_action
      @top_action = Current.family.top_actions.find(params[:id])
    end

    def require_top_action_permission!
      return if Current.user.present?

      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: t("shared.require_user") }
        format.turbo_stream { head :forbidden }
      end
      false
    end
end
