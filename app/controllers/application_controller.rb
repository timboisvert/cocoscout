class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  before_action :show_my_sidebar
  helper_method :impersonating?

  def show_my_sidebar
    @show_my_sidebar = true
  end

  def impersonating?
    session[:user_doing_the_impersonating].present?
  end
end
