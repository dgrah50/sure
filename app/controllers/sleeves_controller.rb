class SleevesController < ApplicationController
  before_action :set_policy_version
  before_action :set_sleeve, only: %i[edit update destroy]

  def new
    @sleeve = @policy_version.sleeves.new
  end

  def create
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t("sleeves.can_only_modify_draft")
      return
    end

    @sleeve = @policy_version.sleeves.new(sleeve_params)

    if @sleeve.save
      redirect_to policy_version_path(@policy_version), notice: t("sleeves.created")
    else
      redirect_to policy_version_path(@policy_version), alert: t("sleeves.error", error: @sleeve.errors.full_messages.to_sentence)
    end
  end

  def edit
  end

  def update
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t("sleeves.can_only_modify_draft")
      return
    end

    @sleeve.update!(sleeve_params)
    redirect_to policy_version_path(@policy_version), notice: t("sleeves.updated")
  end

  def destroy
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t("sleeves.can_only_modify_draft")
      return
    end

    @sleeve.destroy!
    redirect_to policy_version_path(@policy_version), notice: t("sleeves.deleted")
  end

  private

    def set_policy_version
      @policy_version = Current.family.policy_versions.find(params[:policy_version_id])
    end

    def set_sleeve
      @sleeve = @policy_version.sleeves.find(params[:id])
    end

    def sleeve_params
      params.require(:sleeve).permit(
        :name,
        :description,
        :target_percentage,
        :min_percentage,
        :max_percentage,
        :sort_order,
        :color,
        :parent_sleeve_id
      )
    end
end
