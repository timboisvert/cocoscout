# frozen_string_literal: true

# Where the V1.1 app opens: the mode this person last used (production mode
# or My), so the app comes back where they left it. Signed out, the app's
# welcome screen. V1 builds open /my directly and never come here.
class StartController < ApplicationController
  allow_unauthenticated_access

  def show
    if Current.user || resume_session
      redirect_to last_mode_path(Current.user)
    else
      redirect_to turbo_native_app? ? welcome_path : signin_path
    end
  end
end
