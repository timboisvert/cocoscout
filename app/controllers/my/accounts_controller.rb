# frozen_string_literal: true

module My
  # Slim account screen for the mobile app's Account tab. Intentionally
  # narrower than the full /account section — just identity + sign out +
  # notification preferences. Profiles, email/password, organizations,
  # billing, etc. all live under /account on the web.
  class AccountsController < ApplicationController
    def show
      @user = Current.user
      @person = @user.person
    end
  end
end
