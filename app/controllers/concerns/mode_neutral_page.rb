# frozen_string_literal: true

# Pages that belong to neither mode (Account settings, Profile, Groups): opened
# from production mode in the app, they keep production mode's menu and strip
# rather than switching to My's (Tim, 2026-10-29), so they need its
# organization (NativeAppHelper#native_production_mode?). The web draws these
# pages from the last mode already (panel_last_mode_production?) and needs
# nothing here.
module ModeNeutralPage
  extend ActiveSupport::Concern
  include OrganizationContext

  included do
    before_action :keep_production_mode
  end

  private

  def keep_production_mode
    return unless turbo_native_app? && Current.user && in_production_mode?

    set_current_organization
    @keep_production_mode = true if Current.organization
  end
end
