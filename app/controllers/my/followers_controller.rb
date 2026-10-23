# frozen_string_literal: true

module My
  # My Followers (Mailing lists, V1.1): the lists organizations share with
  # you, in one place. See, add, export; only the organizations send.
  class FollowersController < ApplicationController
    before_action :require_authentication
    before_action :require_shares

    PER_PAGE = 50

    def index
      @show_my_sidebar = true
      @my = MyFollowers.new(Current.user)
      @organization_id = params[:organization_id].presence
      @kind = params[:kind].presence_in(FollowerSource::KINDS)
      @q = params[:q].to_s.strip
      @show = params[:show] == "unsubscribed" ? "unsubscribed" : "following"
      all_rows = @my.rows(organization_id: @organization_id, kind: @kind, q: @q.presence)
      @following_count = all_rows.count(&:following?)
      @by_organization = all_rows.select(&:following?).flat_map { |row| row.entries.select(&:following).map(&:organization).uniq }.tally
      rows = all_rows.select { |row| @show == "following" ? row.following? : !row.following? }
      @page = [ params[:page].to_i, 1 ].max
      @total = rows.size
      @rows = rows.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    end

    def create
      my = MyFollowers.new(Current.user)
      list = my.lists.find { |candidate| candidate.id == params[:mailing_list_id].to_i }
      return redirect_to(my_followers_path, alert: "Pick a list to add them to.") unless list
      return redirect_to(my_followers_path, alert: "Confirm they asked to hear about your shows.") unless params[:permission] == "1"

      entries = FollowerIntake.parse("#{params[:name]}, #{params[:email]}")
      added = FollowerIntake.new(list).add!(entries, kind: "added_by_share", added_by_person: my.sharing_person(list) || Current.user.person)
      notice = added.positive? ? "Added to #{list.name}, at #{list.organization.name}." : "They're already on #{list.name}, unsubscribed, or not an email address."
      redirect_to my_followers_path, notice: notice
    end

    # A spreadsheet of everyone still following, emailed (FollowersExportJob).
    def export
      person = MyFollowers.new(Current.user).viewer
      FollowersExportJob.perform_later(person.id, user_id: Current.user.id)
      redirect_to my_followers_path, notice: "We're making the spreadsheet. It'll be in your email in a minute."
    end

    private

    def require_shares
      raise ActiveRecord::RecordNotFound unless Current.user.has_follower_shares?
    end
  end
end
