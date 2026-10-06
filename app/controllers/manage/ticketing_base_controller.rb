# frozen_string_literal: true

module Manage
  # Everything in the Ticketing section. It's a Pro module (the paid-feature
  # gate maps these controllers to :ticketing), for org owners and managers.
  # Open to every Pro organization since 2026-10-06, the first customer live.
  class TicketingBaseController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    private

    def ticketing_profile
      @ticketing_profile ||= TicketingProfile.for(Current.organization)
    end
    helper_method :ticketing_profile

    # The organization's upcoming dates that can still sell, soonest first.
    def upcoming_listings
      @upcoming_listings ||= Current.organization.ticket_listings.joins(:show).includes(:production, :show, :ticket_tiers)
                                    .where.not(status: %w[canceled closed]).where(shows: { canceled: false })
                                    .where("shows.date_and_time > ?", Time.current).order("shows.date_and_time").to_a
    end

    # Every upcoming date's plain ticket types, grouped by production, for a
    # select: "Fri Oct 10, 7:30 PM · General, $20.00" (passes, deals).
    def tier_choices
      upcoming_listings.group_by { |listing| listing.production&.name || "Other" }.map do |production, dates|
        options = dates.flat_map do |listing|
          listing.ticket_tiers.select { |tier| tier.archived_at.nil? && !tier.bundle? }.map do |tier|
            [ "#{listing.show.date_and_time.strftime('%a %b %-d, %-l:%M %p')} · #{tier.name}, #{helpers.number_to_currency(tier.price_cents / 100.0)}", tier.id ]
          end
        end
        [ production, options ]
      end
    end
    helper_method :tier_choices

    # Upcoming dates, grouped by production, for a select.
    def listing_choices
      upcoming_listings.group_by { |listing| listing.production&.name || "Other" }.map do |production, dates|
        [ production, dates.map { |listing| [ listing.show.date_and_time.strftime("%a %b %-d, %-l:%M %p"), listing.id ] } ]
      end
    end
    helper_method :listing_choices

    def production_choices
      Current.organization.productions.order(:name).map { |production| [ production.name, production.id ] }
    end
    helper_method :production_choices
  end
end
