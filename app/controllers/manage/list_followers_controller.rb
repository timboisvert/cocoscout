# frozen_string_literal: true

module Manage
  # Adding people to a list (one, or many pasted, optionally checked first) and taking
  # someone off it.
  class ListFollowersController < ManageController
    before_action :set_list

    # What a paste would add, before anything's added: a fragment the Add
    # people window shows (follower-paste#check).
    def check
      entries = FollowerIntake.new(@list).check(FollowerIntake.parse(params[:text]))
      render partial: "manage/list_followers/check", locals: { entries: entries }
    end

    def create
      intake = FollowerIntake.new(@list)
      if params[:text].present?
        unless params[:permission] == "1"
          return redirect_to(manage_mailing_list_path(@list), alert: "Confirm these people asked to hear from you before adding them.")
        end

        entries = FollowerIntake.parse(params[:text])
        kind = "paste"
      else
        entries = FollowerIntake.parse("#{params[:name]}, #{params[:email]}")
        kind = "manual"
      end
      added = intake.add!(entries, kind: kind, added_by_person: Current.user.person)
      left = entries.size - added
      notice = if added.zero? then "Nobody new to add#{' (they were already on it, unsubscribed, bounced or not an email)' if left.positive?}."
      else "Added #{ActionController::Base.helpers.pluralize(added, 'person')} to #{@list.name}."
      end
      redirect_to manage_mailing_list_path(@list), notice: notice
    end

    def destroy
      follower = @list.followers.find(params[:follower_id])
      @list.mailing_list_memberships.where(follower: follower).destroy_all
      redirect_to manage_mailing_list_path(@list), notice: "#{follower.display_name} is off #{@list.name}."
    end

    private

    def set_list
      @list = Current.organization.mailing_lists.find(params[:id])
    end
  end
end
