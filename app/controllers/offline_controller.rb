# The page the installed app shows without a connection. The service worker
# keeps a copy when it installs, so it's rendered in the app's language; it
# has no session data and inline styles only (nothing else may be cached).
class OfflineController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :redirect_to_setup

  def show
    render layout: false
  end
end
