# frozen_string_literal: true

module Api
  module V1
    class PushTokensController < BaseController
      def create
        device_token = current_user.device_tokens.find_or_initialize_by(
          token: params[:token],
          platform: params[:platform]
        )

        if device_token.save
          render json: { id: device_token.id }, status: :created
        else
          render json: { errors: device_token.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        device_token = current_user.device_tokens.find_by(token: params[:id])

        if device_token
          device_token.destroy
          head :no_content
        else
          head :not_found
        end
      end
    end
  end
end
