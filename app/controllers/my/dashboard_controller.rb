class My::DashboardController < ApplicationController
  def index
    redirect_to my_shows_path
  end
end
