# frozen_string_literal: true

module My
  # The iOS app's push notifications for this phone (bridge/push_controller.js
  # sends what the app reports each time it opens). On: the phone's token,
  # filed under this sign-in, so signing out stops its notifications. Off
  # (turned off in iPhone Settings): the token goes, and the unread-messages
  # email goes back to its usual timing (UnreadDigestJob).
  class PushTokensController < ApplicationController
    APNS_TOKEN = /\A\h{32,200}\z/

    def create
      token = params[:token].to_s.downcase
      return head :unprocessable_content unless token.match?(APNS_TOKEN)

      # A phone that changes hands moves to whoever signed in on it.
      device = DeviceToken.find_or_initialize_by(token: token, platform: "ios")
      device.assign_attributes(user: Current.user, session: Current.session, app_session: nil,
                               apns_environment: params[:environment] == "sandbox" ? "sandbox" : "production")
      # Saved or not, the touch marks this phone as checked in today.
      device.save!
      device.touch unless device.saved_changes?
      head :no_content
    end

    def destroy
      Current.user.device_tokens.where(platform: "ios", token: params[:token].to_s.downcase).destroy_all
      head :no_content
    end
  end
end
