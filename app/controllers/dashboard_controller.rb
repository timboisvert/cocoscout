class DashboardController < ApplicationController
  def index
    if (production = Current.production)
      redirect_to production_path(production)
    end
  end
end
