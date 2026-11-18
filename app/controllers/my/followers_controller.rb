# frozen_string_literal: true

module My
  # My Followers (Tim, 2026-11-17): the mailing lists an organization shares
  # with the people on a contract (SharedFollowers), for a contract that
  # hasn't moved into an organization of their own. They look, search,
  # download and copy the addresses. Nothing is ever sent from here.
  class FollowersController < ApplicationController
    before_action :require_authentication
    before_action { @show_my_sidebar = true }

    def index
      @lists = SharedFollowers.my_lists(Current.user)
      # The ones that now live in an organization they run: a pointer each.
      @moved = SharedFollowers.moved_lists(Current.user)
      return redirect_to(my_dashboard_path) if @lists.empty? && @moved.empty?

      @q = params[:q].to_s.strip
      @rows = @lists.to_h { |list| [ list.id, SharedFollowers.rows(list, q: @q) ] }
    end

    # One list as a spreadsheet, straight to the browser.
    def download
      list = SharedFollowers.my_lists(Current.user).find { |one| one.id == params[:id].to_i }
      return redirect_to(my_followers_path, alert: "That list isn't shared with you.") unless list

      send_data SharedFollowers.csv(list), type: "text/csv",
                filename: "#{list.name.parameterize}-followers-#{Date.current.iso8601}.csv"
    end
  end
end
