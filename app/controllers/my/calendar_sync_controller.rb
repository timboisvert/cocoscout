# frozen_string_literal: true

module My
  class CalendarSyncController < ApplicationController
    def settings
      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a

      # Initialize sync entities if not set
      if @person.calendar_sync_entities.blank?
        @person.calendar_sync_entities = { "person" => true }
        @groups.each do |group|
          @person.calendar_sync_entities["group_#{group.id}"] = false
        end
      end
    end

    def update_settings
      @person = Current.user.person
      @groups = @person.groups.active.order(:name).to_a

      # Build sync entities from params
      sync_entities = {}
      sync_entities["person"] = params[:sync_person] == "1"

      @groups.each do |group|
        sync_entities["group_#{group.id}"] = params["sync_group_#{group.id}"] == "1"
      end

      @person.calendar_sync_enabled = params[:calendar_sync_enabled] == "1"
      @person.calendar_sync_scope = params[:calendar_sync_scope]
      @person.calendar_sync_entities = sync_entities

      if @person.save
        redirect_to my_shows_path, notice: "Calendar sync settings updated successfully."
      else
        render :settings
      end
    end

    def confirm_email
      @person = Current.user.person

      # Mark email as confirmed. Future enhancement: send confirmation link via email
      @person.calendar_sync_email_confirmed = true

      if @person.save
        redirect_to my_calendar_sync_settings_path, notice: "Email confirmed for calendar sync."
      else
        redirect_to my_calendar_sync_settings_path, alert: "Failed to confirm email."
      end
    end

    def disable
      @person = Current.user.person
      @person.calendar_sync_enabled = false

      if @person.save
        redirect_to my_shows_path, notice: "Calendar sync disabled."
      else
        redirect_to my_shows_path, alert: "Failed to disable calendar sync."
      end
    end
  end
end
