# frozen_string_literal: true

module My
  # Inline updates from the dashboard "complete your info" panel. Each action
  # updates the user's primary person and returns to the dashboard so the panel
  # re-renders with the gap resolved.
  class ProfileCompletionController < ApplicationController
    before_action :set_person

    def update_contact
      if @person.update(phone: contact_params[:phone])
        redirect_to my_dashboard_path, notice: "Contact info saved."
      else
        redirect_to my_dashboard_path, alert: "Couldn't save contact info: #{@person.errors.full_messages.to_sentence}"
      end
    end

    def update_headshot
      image = params.dig(:person, :image)
      if image.blank?
        redirect_to my_dashboard_path, alert: "Choose a photo to upload." and return
      end

      headshot = @person.profile_headshots.new(
        position: (@person.profile_headshots.maximum(:position) || -1) + 1,
        is_primary: @person.profile_headshots.none?
      )
      headshot.image.attach(image)

      if headshot.save
        redirect_to my_dashboard_path, notice: "Headshot uploaded."
      else
        redirect_to my_dashboard_path, alert: "Couldn't upload headshot: #{headshot.errors.full_messages.to_sentence}"
      end
    end

    private

    def set_person
      @person = Current.user.person
      redirect_to my_dashboard_path, alert: "No profile found." unless @person
    end

    def contact_params
      params.require(:person).permit(:phone)
    end
  end
end
