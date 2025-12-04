class HomeController < ApplicationController
  allow_unauthenticated_access

  # Use the public facing layout
  layout "home"

  def index
  end
end
