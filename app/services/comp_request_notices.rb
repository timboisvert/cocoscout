# frozen_string_literal: true

# Who is notified about a request for more comps on one date, and in what
# words (CompRequestTemplates). Notifications only, never an email (Tim,
# 2026-11-20). A request goes to the organization's owners and managers; the
# decision, with any comment, goes back to whoever requested it.
class CompRequestNotices
  REQUESTED_KINDS = %w[comp_request_requested].freeze

  class << self
    def requested(request)
      listing = request.ticket_listing
      path = routes.manage_ticket_listing_path(listing)
      requester = request.requested_by.person&.name.presence || request.requested_by.email_address
      manager_ids(listing.organization).each do |user|
        deliver(user, request, kind: "comp_request_requested", path: path,
                variables: { requester_name: requester, side_words: request.side_words, note: request.note.to_s, listing_url: path })
      end
    end

    def approved(request)
      words = if request.approved_quantity == request.quantity then "your request for #{more_comps(request.quantity)}"
      else "#{request.approved_quantity} of the #{more_comps(request.quantity)} you requested"
      end
      to_requester(request, kind: "comp_request_approved", variables: { approved_words: words, comment: request.comment.to_s })
    end

    def declined(request)
      to_requester(request, kind: "comp_request_declined", variables: { comment: request.comment.to_s })
    end

    def closed(request)
      words = if request.closed_reason == "showtime" then "the date started before anyone decided it"
      else "#{request.organization.name} no longer takes comp requests for that date"
      end
      to_requester(request, kind: "comp_request_closed", variables: { closed_words: words })
    end

    # A request decided, withdrawn, or closed: the managers' notifications
    # about it that nobody has opened are removed, so nobody is sent to a
    # request that is no longer waiting. Opened ones stay, as history.
    def retract(request)
      Notification.where(subject: request, kind: REQUESTED_KINDS, read_at: nil).delete_all
    end

    # "4 more comps" / "1 more comp".
    def more_comps(count) = "#{count} more #{count == 1 ? 'comp' : 'comps'}"

    # Where the requester's side issues comps for the date.
    def comps_path(request)
      show = request.show
      request.contract? ? routes.my_show_tickets_path(show) : routes.manage_production_sale_path(show.production, request.ticket_listing)
    end

    private

    def manager_ids(organization)
      ids = organization.organization_roles.where(company_role: "manager").pluck(:user_id) + [ organization.owner_id ]
      User.where(id: ids.compact.uniq).to_a
    end

    def to_requester(request, kind:, variables:)
      path = comps_path(request)
      deliver(request.requested_by, request, kind: kind, path: path,
              variables: variables.merge(organization_name: request.organization.name, comps_url: path))
    end

    def deliver(user, request, kind:, path:, variables:)
      show = request.show
      zone = request.organization.time_zone.presence || Time.zone.name
      at = show.date_and_time.in_time_zone(zone)
      Notifier.deliver(user: user, category: "ticketing_sales", kind: kind, template_key: kind, path: path,
                       organization: request.organization, subject: request,
                       variables: { production_name: show.production.name, date_words: at.strftime("%A, %B %-d at %-l:%M %p"),
                                    more_comps: more_comps(request.quantity) }.merge(variables))
    rescue StandardError => e
      # A notice that can't be sent never undoes the request or the decision.
      Rails.logger.error("[CompRequestNotices] request #{request.id} #{kind}: #{e.class}: #{e.message}")
      nil
    end

    def routes = Rails.application.routes.url_helpers
  end
end
