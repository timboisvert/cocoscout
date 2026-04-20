# frozen_string_literal: true

module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_api_user!, only: :create

      def create
        user = User.find_by(email_address: params[:email])

        if user&.authenticate(params[:password])
          render json: { token: user.generate_token_for(:api), user_id: user.id }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      def destroy
        if current_user
          current_user.device_tokens.where(token: params[:device_token]).destroy_all if params[:device_token].present?
          render json: { message: "Signed out" }
        else
          render_unauthorized
        end
      end
    end
  end
end
