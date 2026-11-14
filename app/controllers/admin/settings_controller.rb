class Admin::SettingsController < ApplicationController
  before_action :require_admin!

  def edit
    @values = %w[max_upload_mb backups_kept offsite_backups_kept documents_claude_text].index_with { Setting.integer(_1) }
  end

  def update
    submitted = params.fetch(:settings, {}).permit(:max_upload_mb, :backups_kept, :offsite_backups_kept, :documents_claude_text).to_h
    records = Setting.update_integers(submitted)
    @errors = records.flat_map { _1.errors.full_messages }
    if @errors.empty?
      Rails.logger.info("[settings] #{current_user.email_address} changed #{submitted.inspect}")
      redirect_to edit_admin_settings_path, notice: t("flash.admin_settings.settings_saved")
    else
      @values = %w[max_upload_mb backups_kept offsite_backups_kept documents_claude_text].index_with { Setting.integer(_1) }.merge(submitted)
      render :edit, status: :unprocessable_entity
    end
  end
end
