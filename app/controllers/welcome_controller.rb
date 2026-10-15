# frozen_string_literal: true

# The app's first screen for someone signed out (Tim, 2026-10-15): Coco, what
# CocoScout is for them, and Sign in / Create an account, instead of dropping
# them on the sign-in form. Signed-out app visits land here
# (Authentication#request_authentication), and so does signing out in the
# app. The website keeps its own home page and sign-in.
class WelcomeController < ApplicationController
  allow_unauthenticated_access

  def show
    return redirect_to(signin_path) unless turbo_native_app?
    redirect_to my_dashboard_path if authenticated?
  end
end
