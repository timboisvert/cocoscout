# frozen_string_literal: true

module Manage
  # The followers another organization shares with this one through a
  # connected contract (SharedFollowers), as a page of its own: look,
  # search, download and copy. It is what Mailing lists opens as on the
  # free plan (PaidFeatureGate sends a free organization here when a
  # connection has brought a list), so it sits outside the Pro module on
  # purpose. Sending is Pro's: there the same followers are the
  # organization's own, in Mailing lists. For owners and managers.
  class SharedFollowersController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    def index
      @lists = SharedFollowers.lists_for_organization(Current.organization).to_a
      return redirect_to(manage_path) if @lists.empty?

      @pro = Current.organization.feature_available?(:mailing_lists)
      @q = params[:q].to_s.strip
      @rows = @lists.to_h { |list| [ list.id, SharedFollowers.rows(list, q: @q) ] }
    end

    def download
      list = SharedFollowers.lists_for_organization(Current.organization).find_by(id: params[:id])
      return redirect_to(manage_shared_followers_path, alert: "That list isn't shared with #{Current.organization.name}.") unless list

      send_data SharedFollowers.csv(list), type: "text/csv",
                filename: "#{list.name.parameterize}-followers-#{Date.current.iso8601}.csv"
    end
  end
end
