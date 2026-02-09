# frozen_string_literal: true

require "aws-sdk-sns"

# Service for sending SMS messages via AWS SNS
#
# Usage:
#   SmsService.send_sms(
#     phone: "5551234567",
#     message: "Your show has been cancelled",
#     sms_type: "show_cancellation",
#     user: current_user,
#     production: @production
#   )
#
class SmsService
  include Rails.application.routes.url_helpers

  class SmsError < StandardError; end

  class << self
    include Rails.application.routes.url_helpers
    def send_sms(phone:, message:, sms_type:, user: nil, organization: nil, production: nil)
      # Normalize phone to 10 digits
      normalized_phone = normalize_phone(phone)

      return nil if normalized_phone.blank?

      # Create log entry
      sms_log = SmsLog.create!(
        phone: normalized_phone,
        message: message,
        sms_type: sms_type,
        status: "pending",
        user: user,
        organization: organization,
        production: production
      )

      begin
        # Check if SNS is configured
        unless sns_configured?
          Rails.logger.warn("SMS not sent - AWS SNS not configured")
          sms_log.update!(
            status: "failed",
            error_message: "AWS SNS not configured"
          )
          return sms_log
        end

        # Check for test mode (development only)
        if test_mode?
          Rails.logger.info("SMS Test Mode: Would send to +1#{normalized_phone}: #{truncate_message(message)}")
          sms_log.update!(
            status: "sent",
            sns_message_id: "TEST_MODE_#{SecureRandom.hex(8)}",
            sent_at: Time.current
          )
          return sms_log
        end

        response = sns_client.publish(
          phone_number: "+1#{normalized_phone}",
          message: truncate_message(message),
          message_attributes: {
            "AWS.SNS.SMS.SMSType" => {
              data_type: "String",
              string_value: "Transactional"
            }
          }
        )

        sms_log.update!(
          status: "sent",
          sns_message_id: response.message_id,
          sent_at: Time.current
        )

        sms_log
      rescue Aws::SNS::Errors::ServiceError => e
        sms_log.update!(
          status: "failed",
          error_message: e.message
        )
        Rails.logger.error("SMS delivery failed: #{e.message}")
        sms_log
      rescue StandardError => e
        sms_log.update!(
          status: "failed",
          error_message: e.message
        )
        Rails.logger.error("SMS delivery failed: #{e.message}")
        sms_log
      end
    end

    def send_show_cancellation(user:, show:)
      return nil unless user.sms_notification_enabled?("show_cancellation")

      phone = user.sms_phone
      return nil unless phone.present?

      production = show.production
      dashboard_url = my_dashboard_url(host: default_host)

      template = ContentTemplate.active.find_by(key: "sms_show_cancellation")
      message = if template
        template.render_body({
          "production_name" => production.name,
          "show_name" => show.display_name,
          "show_date" => show.date_and_time.strftime("%b %-d"),
          "dashboard_url" => dashboard_url
        })
      else
        "CocoScout: #{production.name} - #{show.display_name} on #{show.date_and_time.strftime('%b %-d')} cancelled. #{dashboard_url} Reply STOP to opt out."
      end

      send_sms(
        phone: phone,
        message: message,
        sms_type: "show_cancellation",
        user: user,
        production: production,
        organization: production.organization
      )
    end

    def send_vacancy_notification(user:, vacancy:, event:, invitation: nil)
      return nil unless user.sms_notification_enabled?("vacancy_notification")

      phone = user.sms_phone
      return nil unless phone.present?

      show = vacancy.show
      production = show.production
      role = vacancy.role

      message = case event.to_s
      when "created"
        # If we have the invitation, link directly to claim page; otherwise link to dashboard
        link = if invitation&.token
          claim_vacancy_url(invitation.token, host: default_host)
        else
          my_dashboard_url(host: default_host)
        end
        template = ContentTemplate.active.find_by(key: "sms_vacancy_created")
        if template
          template.render_body({
            "role_name" => role.name,
            "production_name" => production.name,
            "show_date" => show.date_and_time.strftime("%b %-d"),
            "link" => link
          })
        else
          "CocoScout: Vacancy for #{role.name} in #{production.name} on #{show.date_and_time.strftime('%b %-d')}. #{link} Reply STOP to opt out."
        end
      when "filled"
        template = ContentTemplate.active.find_by(key: "sms_vacancy_filled")
        if template
          template.render_body({
            "role_name" => role.name,
            "production_name" => production.name,
            "show_date" => show.date_and_time.strftime("%b %-d")
          })
        else
          "CocoScout: Vacancy filled - #{role.name} for #{production.name} on #{show.date_and_time.strftime('%b %-d')}. Reply STOP to opt out."
        end
      else
        return nil
      end

      send_sms(
        phone: phone,
        message: message,
        sms_type: "vacancy_notification",
        user: user,
        production: production,
        organization: production.organization
      )
    end

    # Test mode methods - only works in development
    def test_mode=(value)
      Thread.current[:sms_test_mode] = value if Rails.env.development?
    end

    def test_mode?
      Rails.env.development? && Thread.current[:sms_test_mode] == true
    end

    private

    def sns_configured?
      ENV["AWS_ACCESS_KEY_ID"].present? &&
        ENV["AWS_SECRET_ACCESS_KEY"].present?
    end

    def sns_client
      @sns_client ||= Aws::SNS::Client.new(
        region: ENV.fetch("AWS_REGION", "us-east-1"),
        access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
      )
    end

    def default_host
      ENV.fetch("APP_HOST", "cocoscout.com")
    end

    def normalize_phone(phone)
      return nil if phone.blank?

      phone.to_s.gsub(/\D/, "").last(10)
    end

    def truncate_message(message, max_length: 160)
      return message if message.length <= max_length

      "#{message[0...(max_length - 3)]}..."
    end
  end
end
