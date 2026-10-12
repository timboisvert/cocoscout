# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_api_user!, only: :create

      # authenticate_by takes as long for an email with no account as for
      # one with a wrong password, so sign-in never reveals who has one.
      def create
        user = User.authenticate_by(email_address: params[:email].to_s, password: params[:password].to_s)

        if user
          _session, token = AppSession.start!(user, device_name: params[:device_name], user_agent: request.user_agent,
                                                    ip_address: request.remote_ip)
          render json: { token: token, user_id: user.id }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      # Ends this phone's session (its push token goes with it); the token
      # stops working at once.
      def destroy
        current_user.device_tokens.where(token: params[:device_token]).destroy_all if params[:device_token].present?
        current_app_session.destroy!
        render json: { message: "Signed out" }
      end
    end
  end
end
