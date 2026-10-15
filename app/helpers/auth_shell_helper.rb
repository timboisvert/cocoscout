# frozen_string_literal: true

# Bits shared by every page built on shared/auth/_shell: sign in, create
# account, forgot and reset password, and the invitation pages (which live
# under Manage::ManageController, so they can't lean on ApplicationController's
# helper methods).
module AuthShellHelper
  # The one text-input style on these pages. text-base (16px) keeps iPhone
  # from zooming in on a tapped field.
  def auth_input_class(error: false)
    border = error ? "border-pink-500" : "border-gray-300"
    "block w-full rounded-lg border #{border} bg-white px-3 py-2.5 text-base text-slate-900 shadow-sm " \
      "placeholder:text-slate-400 focus:border-pink-500 focus:outline-none focus:ring-2 focus:ring-pink-500"
  end

  # The Hotwire Native app, regardless of which controller root rendered us.
  def auth_native_app?
    request.user_agent.to_s.include?("Turbo Native")
  end

  # "2 hours": what the forgot-password copy promises, straight from the model.
  def password_reset_link_lifetime
    pluralize(User::PASSWORD_RESET_LINK_LIFETIME.in_hours.round, "hour")
  end
end
