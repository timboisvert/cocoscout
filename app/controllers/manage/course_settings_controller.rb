# frozen_string_literal: true

module Manage
  # Org-level course settings. Today the only topic is how the organization gets
  # paid its course revenue — CocoScout collects registration money and remits
  # the org's share to its own Stripe Connect account, and this is where that
  # bank gets connected. Lives in Courses (a free module), not the Pro-only
  # Money section. Uses the shared settings layout, so a second topic (refund
  # policy, instructor defaults) is just a new entry in SECTIONS.
  class CourseSettingsController < Manage::ManageController
    SECTIONS = %w[payments].freeze
    DEFAULT_SECTION = "payments"

    before_action :set_section, only: %i[show]

    def show
      @organization = Current.organization
      # Re-sync from Stripe so a just-finished (or still-verifying) account is
      # reflected here even when the account.updated webhook didn't reach us.
      if @organization.connect_account_started? && Stripe.api_key.present?
        begin
          @account_status = StripeConnectService.new(@organization).refresh_status
        rescue StripeConnectService::Error => e
          Rails.logger.warn("Course settings: status refresh failed — #{e.message}")
        end
      end
    end

    # Kick off (or resume) Stripe Express onboarding for the organization.
    def connect
      start_bank_onboarding
    end

    # Stripe redirects here when the onboarding link expires — hand back a fresh one.
    def connect_refresh
      start_bank_onboarding
    end

    # Stripe redirects here after the org finishes (or exits) onboarding.
    def connect_return
      StripeConnectService.new(Current.organization).sync_account
      notice = if Current.organization.can_receive_payouts?
        "Your organization's bank is connected — course payouts can be sent straight to you."
      else
        "Almost there — finish the remaining steps so your organization can get paid."
      end
      redirect_to manage_course_settings_path, notice: notice
    rescue StripeConnectService::Error
      redirect_to manage_course_settings_path,
        alert: "We couldn't confirm your bank setup. Please try again."
    end

    private

    def sections
      SECTIONS.map do |key|
        { key: key, label: key.titleize, path: manage_course_settings_section_path(section: key) }
      end
    end
    helper_method :sections

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to manage_course_settings_path unless @section.in?(SECTIONS)
    end

    def start_bank_onboarding
      url = StripeConnectService.new(Current.organization).onboarding_link(
        return_url: manage_course_settings_return_url,
        refresh_url: manage_course_settings_refresh_url
      )
      redirect_to url, allow_other_host: true
    rescue StripeConnectService::Error => e
      redirect_to manage_course_settings_path, alert: "Couldn't start bank setup: #{e.message}"
    end
  end
end
