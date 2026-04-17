class GuardrailsController < ApplicationController
  before_action :set_policy_version
  before_action :set_guardrail, only: %i[edit update destroy]
  before_action :check_draft_policy, only: %i[create update destroy]

  def new
    @guardrail = @policy_version.guardrails.new(
      enabled: true,
      severity: "warning",
      configuration: { "threshold" => 5.0 }
    )
  end

  def create
    @guardrail = @policy_version.guardrails.new(guardrail_params)

    if @guardrail.save
      redirect_to policy_version_path(@policy_version), notice: t(".created")
    else
      redirect_to policy_version_path(@policy_version), alert: t(".error", error: @guardrail.errors.full_messages.to_sentence)
    end
  end

  def edit
  end

  def update
    @guardrail.update!(guardrail_params)
    redirect_to policy_version_path(@policy_version), notice: t(".updated")
  end

  def destroy
    @guardrail.destroy!
    redirect_to policy_version_path(@policy_version), notice: t(".deleted")
  end

  private

    def set_policy_version
      @policy_version = Current.family.policy_versions.find(params[:policy_version_id])
    end

    def set_guardrail
      @guardrail = @policy_version.guardrails.find(params[:id])
    end

    def check_draft_policy
      unless @policy_version.draft?
        redirect_to policy_version_path(@policy_version), alert: "Can only modify draft policies"
      end
    end

    def guardrail_params
      params.require(:guardrail).permit(
        :name,
        :guardrail_type,
        :severity,
        :enabled,
        configuration: {}
      )
    end
end
