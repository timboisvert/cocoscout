# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods
      include SentryContext

      before_action :authenticate_api_user!

      private

      # A bearer token names one signed-in phone (AppSession).
      def authenticate_api_user!
        authenticate_with_http_token do |token, _options|
          if (session = AppSession.authenticate(token))
            @current_app_session = session
            @current_api_user = session.user
          end
        end or render_unauthorized
      end

      def current_user
        @current_api_user
      end

      def current_app_session
        @current_app_session
      end

      # Make Current.user available for services that depend on it
      def render_unauthorized
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
