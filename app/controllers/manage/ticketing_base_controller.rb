# frozen_string_literal: true

module Manage
  # Everything in the Ticketing section. It's a Pro module (the paid-feature
  # gate maps these controllers to :ticketing), for org owners and managers,
  # and while ticketing is experimental, for superadmins only. Drop
  # ensure_user_is_superadmin when it opens up.
  class TicketingBaseController < Manage::ManageController
    before_action :ensure_user_is_superadmin
    before_action :ensure_org_owner_or_manager

    private

    def ticketing_profile
      @ticketing_profile ||= TicketingProfile.for(Current.organization)
    end
    helper_method :ticketing_profile
  end
end
