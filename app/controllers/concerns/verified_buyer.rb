# frozen_string_literal: true

# A buyer who proved their email for one organization (an emailed code,
# Ticketing::BuyerVerification) carries a thirty-day encrypted cookie for
# that organization. Memberships read it today; V1.6's buyer hub adds pages
# behind the same cookie.
module VerifiedBuyer
  extend ActiveSupport::Concern

  COOKIE_DAYS = 30

  included do
    helper_method :verified_buyer_email, :current_membership if respond_to?(:helper_method)
  end

  def verified_buyer_email(organization)
    return nil unless organization

    data = cookies.encrypted["buyer_#{organization.id}"]
    data.is_a?(Hash) ? data["email"].presence : nil
  rescue StandardError
    nil
  end

  def verify_buyer!(organization, email)
    cookies.encrypted["buyer_#{organization.id}"] = { value: { "email" => email.to_s.strip.downcase, "at" => Time.current.iso8601 },
                                                      expires: COOKIE_DAYS.days.from_now, httponly: true, same_site: :lax }
  end

  def forget_buyer!(organization)
    cookies.delete("buyer_#{organization.id}")
  end

  # The verified buyer's membership with this organization, if it's live.
  def current_membership(organization)
    return @current_membership if defined?(@current_membership) && @current_membership_org == organization&.id

    @current_membership_org = organization&.id
    email = verified_buyer_email(organization)
    @current_membership = email && organization.ticket_memberships.live.where(holder_email: email).includes(:level).order(ends_on: :desc).first
  end
end
