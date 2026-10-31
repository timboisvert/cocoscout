# frozen_string_literal: true

module Manage
  # Accessibility for a location, and for a room (accessibility plan §1):
  # Yes / No / Ask us and a note per feature, who to ask, and the room-only
  # facts. A room answers "same as the location" unless marked different
  # here. Free on every plan: rooms never depend on Ticketing.
  class AccessProfilesController < ManageController
    before_action :ensure_user_is_global_manager, only: :update
    before_action :set_owner

    def edit
      @profile = AccessProfile.for(@owner)
    end

    def update
      answers = params.fetch(:answers, {}).permit!.to_h
      notes = params.fetch(:notes, {}).permit!.to_h
      AccessAnswer.transaction do
        AccessFeatures::KEYS.each do |key|
          answer = answers[key].to_s
          row = @owner.access_answers.find_by(feature_key: key)
          if AccessFeatures::ANSWERS.include?(answer)
            (row || @owner.access_answers.build(feature_key: key)).update!(answer: answer, note: notes[key].to_s.strip.first(200).presence, updated_by: Current.user)
          else
            # "Same as the location" on a room, or cleared on a location.
            row&.destroy!
          end
        end
        if @space
          @space.update!(params.fetch(:location_space, {}).permit(:wheelchair_spaces, :wheelchair_spaces_note, :stage_access, :floor_label))
        else
          @location.update!(params.fetch(:location, {}).permit(:access_email, :access_phone))
        end
      end
      redirect_to (@space ? manage_location_space_path(@location, @space) : manage_location_path(@location)), notice: "Accessibility saved."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to (@space ? manage_location_space_access_path(@location, @space) : manage_location_access_path(@location)), alert: e.record.errors.full_messages.to_sentence
    end

    private

    def set_owner
      @location = Current.organization.locations.find(params[:location_id])
      @space = params[:space_id].present? ? @location.location_spaces.find(params[:space_id]) : nil
      @owner = @space || @location
    end
  end
end
