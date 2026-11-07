class Admin::SettingsController < ApplicationController
  before_action :require_admin!

  def edit
    @values = Setting::INTEGERS.keys.index_with { Setting.integer(_1) }
  end

  def update
    submitted = params.fetch(:settings, {}).permit(*Setting::INTEGERS.keys).to_h
    records = Setting.update_integers(submitted)
    @errors = records.flat_map { _1.errors.full_messages }
    if @errors.empty?
      Rails.logger.info("[settings] #{current_user.email_address} changed #{submitted.inspect}")
      redirect_to edit_admin_settings_path, notice: "Settings saved."
    else
      @values = Setting::INTEGERS.keys.index_with { Setting.integer(_1) }.merge(submitted)
      render :edit, status: :unprocessable_entity
    end
  end
end
