class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method

  before_action :track_my_dashboard
  before_action :show_my_sidebar

  def track_my_dashboard
    # Only track if user is on a My:: controller page (not AuthController or other base controllers)
    if self.class.name.start_with?("My::") && Current.user.present?
      cookies.encrypted[:last_dashboard] = { value: "my", expires: 1.year.from_now }
      Rails.logger.info "🔍 Dashboard tracking - Setting to 'my' from #{self.class.name}"
    end
  end

  def show_my_sidebar
    @show_my_sidebar = true
  end
end
