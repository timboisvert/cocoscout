# frozen_string_literal: true

module My
  # The app's push notifications for this phone (bridge/push_controller.js
  # sends what the app reports each time it opens). On: the phone's token,
  # filed under this sign-in, so signing out stops its notifications. Off
  # (turned off in the phone's Settings): the token goes, and the
  # unread-messages email goes back to its usual timing (UnreadDigestJob).
  # iPhones send Apple's token; Android phones say platform "android" and
  # send Firebase's, which is case-sensitive.
  class PushTokensController < ApplicationController
    APNS_TOKEN = /\A\h{32,200}\z/
    FCM_TOKEN = /\A[\w\-:]{32,4096}\z/

    def create
      return head :unprocessable_content unless token.match?(android? ? FCM_TOKEN : APNS_TOKEN)

      # A phone that changes hands moves to whoever signed in on it.
      device = DeviceToken.find_or_initialize_by(token: token, platform: platform)
      device.assign_attributes(user: Current.user, session: Current.session, app_session: nil,
                               apns_environment: params[:environment] == "sandbox" ? "sandbox" : "production")
      # Saved or not, the touch marks this phone as checked in today.
      device.save!
      device.touch unless device.saved_changes?
      head :no_content
    end

    def destroy
      Current.user.device_tokens.where(platform: platform, token: token).destroy_all
      head :no_content
    end

    private

    def android? = params[:platform] == "android"

    def platform = android? ? "android" : "ios"

    def token
      android? ? params[:token].to_s : params[:token].to_s.downcase
    end
  end
end
