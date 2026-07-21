# frozen_string_literal: true

module Manage
  # How the organization gets paid its course revenue. CocoScout collects course
  # registration money and remits the org's share to the org's own Stripe Connect
  # account — this is where the org connects that bank. Lives in Courses (a free
  # module), not the Pro-only Money section.
  class CoursePayoutSettingsController < Manage::ManageController
    def show
      @organization = Current.organization
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
      redirect_to manage_course_payout_settings_path, notice: notice
    rescue StripeConnectService::Error
      redirect_to manage_course_payout_settings_path,
        alert: "We couldn't confirm your bank setup. Please try again."
    end

    private

    def start_bank_onboarding
      url = StripeConnectService.new(Current.organization).onboarding_link(
        return_url: manage_course_payout_settings_return_url,
        refresh_url: manage_course_payout_settings_refresh_url
      )
      redirect_to url, allow_other_host: true
    rescue StripeConnectService::Error => e
      redirect_to manage_course_payout_settings_path, alert: "Couldn't start bank setup: #{e.message}"
    end
  end
end
