class Admin::AboutController < ApplicationController
  before_action :require_admin!

  def show
    @info = SystemInfo.new
  end
end
