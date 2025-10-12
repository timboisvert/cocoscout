class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend

  before_action :show_my_sidebar

  def show_my_sidebar
    @show_my_sidebar = true
  end
end
