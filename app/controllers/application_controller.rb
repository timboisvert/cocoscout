class ApplicationController < ActionController::Base
  include Authentication

  before_action :show_app_sidebar

  def show_app_sidebar
    @show_app_sidebar = true
  end
end
