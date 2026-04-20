# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_api_user!

      private

      def authenticate_api_user!
        authenticate_with_http_token do |token, _options|
          if (user = User.find_by_token_for(:api, token))
            @current_api_user = user
          end
        end or render_unauthorized
      end

      def current_user
        @current_api_user
      end

      # Make Current.user available for services that depend on it
      def render_unauthorized
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
