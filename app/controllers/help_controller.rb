# The user guide (docs/guide), including the instructions for electronic
# records and signatures (AC 120-78B 2.2.12, 3.2.9).
class HelpController < ApplicationController
  def show
    @page = HelpGuide.find(params[:page] || "README") or raise ActionController::RoutingError, "Not found"
    @pages = HelpGuide.pages
  end
end
