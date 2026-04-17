class PolicyVersionsController < ApplicationController
  before_action :set_policy_version, only: %i[show edit update destroy publish archive]

  def index
    @policy_versions = Current.family.policy_versions
                              .order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END"))
                              .order(created_at: :desc)
  end

  def show
    @sleeves = @policy_version.sleeves
    @guardrails = @policy_version.guardrails
  end

  def new
    @policy_version = Current.family.policy_versions.new
  end

  def create
    @policy_version = Current.family.policy_versions.new(policy_version_params)
    @policy_version.created_by = Current.user

    if @policy_version.save
      redirect_to policy_version_path(@policy_version), notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t(".cannot_edit_non_draft")
    end
  end

  def update
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t(".cannot_edit_non_draft")
      return
    end

    if @policy_version.update(policy_version_params)
      redirect_to policy_version_path(@policy_version), notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t(".cannot_delete_non_draft")
      return
    end

    @policy_version.destroy!
    redirect_to policy_versions_path, notice: t(".deleted")
  end

  def publish
    unless @policy_version.draft?
      redirect_to policy_version_path(@policy_version), alert: t(".cannot_publish_non_draft")
      return
    end

    if @policy_version.activate!
      redirect_to policy_version_path(@policy_version), notice: t(".published")
    else
      redirect_to policy_version_path(@policy_version), alert: t(".publish_failed")
    end
  end

  def archive
    unless @policy_version.active?
      redirect_to policy_version_path(@policy_version), alert: t(".cannot_archive_non_active")
      return
    end

    if @policy_version.archive!
      redirect_to policy_version_path(@policy_version), notice: t(".archived")
    else
      redirect_to policy_version_path(@policy_version), alert: t(".archive_failed")
    end
  end

  private

    def set_policy_version
      @policy_version = Current.family.policy_versions.find(params[:id])
    end

    def policy_version_params
      params.require(:policy_version).permit(:name, :description, :effective_date)
    end
end
