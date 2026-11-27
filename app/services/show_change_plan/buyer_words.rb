# frozen_string_literal: true

class ShowChangePlan
  # The buyer emails of a date change: one per buyer, listing all of their
  # tickets. The manager reads and edits one draft (plain text, the way the
  # ticketing emails are edited); each buyer's own parts are filled in at
  # send time from what actually happened to their orders.
  module BuyerWords
    module_function

    KEYS = { cancel: "date_change_buyers_canceled", move: "date_change_buyers_moved",
             rebook: "date_change_buyers_rebooked", back_on: "date_change_buyers_back_on" }.freeze

    def draft(kind)
      template = ContentTemplateService.find_template(KEYS.fetch(kind))
      { subject: template.subject.to_s, body: TicketOrderMailer.plain_text(template.body) }
    end

    def money(cents) = ActiveSupport::NumberHelper.number_to_currency(cents.to_i / 100.0)
    def tickets(count) = ActionController::Base.helpers.pluralize(count, "ticket")
    def when_words(time) = "#{time.strftime('%A, %B %-d')} at #{time.strftime('%-l:%M %p').strip}"
    def first_name(order) = order.buyer_name.to_s.split.first.presence || "there"

    def common(order, orders)
      { "first_name" => first_name(order), "organization_name" => order.organization.name,
        "show_title" => orders.map { |o| o.ticket_listing.display_title }.uniq.to_sentence }
    end

    # What happened to each of a buyer's orders on canceled dates, in their
    # words. results: [[order, :refunded, refund] | [order, :marked, refund]
    # | [order, :credit] | [order, :comp]]
    def canceled_variables(results)
      orders = results.map(&:first)
      lines = results.map do |order, outcome, refund|
        count = refund&.ticket_ids&.size.presence || order.tickets.count { |t| t.status.in?(Ticket::SOLD_STATUSES) || t.status == "refunded" }
        case outcome
        when :refunded
          "We've refunded #{money(refund.amount_cents)} for your #{tickets(count)}. #{TicketOrderMailer.refund_where_words(refund)}"
        when :marked
          if order.money_path == "cash"
            "You paid #{money(refund.amount_cents)} at the door for your #{tickets(count)}. Reply to this email to arrange getting it back."
          else
            "You bought your #{tickets(count)} through another seller. Reply to this email about getting your money back."
          end
        when :credit
          "The #{count == 1 ? 'credit' : 'credits'} you used for your #{tickets(count)} #{count == 1 ? 'is' : 'are'} back on your pass, ready for another show."
        when :comp
          "Your complimentary #{tickets(count)} no longer #{count == 1 ? 'works' : 'work'}."
        end
      end
      common(orders.first, orders).merge(
        "dates" => orders.map { |o| when_words(o.ticket_listing.show.date_and_time) }.uniq.to_sentence,
        "what_happens" => lines.uniq.join(" ")
      )
    end

    # A buyer's orders on moved dates: was and now for each, and the refund
    # link when the manager offers one (never for comps).
    def moved_variables(change, orders, was_by_show:, offer_refund:)
      lines = orders.map do |order|
        show = order.ticket_listing.show
        was = was_by_show[show.id] || order.told_starts_at
        "Your tickets for #{when_words(was)} are now for #{when_words(show.date_and_time)}."
      end
      paying = orders.find { |o| o.money_path != "none" }
      common(orders.first, orders).merge(
        "changes" => lines.uniq.join(" "),
        "refund_link" => (offer_refund && paying ? refund_url(change, paying) : "")
      )
    end

    def rebooked_variables(change, old_order, new_order, offer_refund:)
      common(old_order, [ old_order ]).merge(
        "was" => when_words(old_order.ticket_listing.show.date_and_time),
        "now" => when_words(new_order.ticket_listing.show.date_and_time),
        "order_url" => routes.tickets_order_url(token: new_order.token, **TicketOrderMailer.url_options),
        "refund_link" => (offer_refund && new_order.money_path != "none" ? refund_url(change, new_order) : "")
      )
    end

    def back_on_variables(orders)
      listing = orders.first.ticket_listing
      common(orders.first, orders).merge(
        "dates" => orders.map { |o| when_words(o.ticket_listing.show.date_and_time) }.uniq.to_sentence,
        "buy_url" => buy_url(listing)
      )
    end

    def refund_url(change, order)
      routes.tickets_date_change_refund_url(token: order.token, change_id: change.id, **TicketOrderMailer.url_options)
    end

    def buy_url(listing)
      profile = TicketingProfile.for(listing.organization)
      routes.tickets_event_url(org: profile.slug, event: listing.slug, **TicketOrderMailer.url_options)
    rescue StandardError
      ""
    end

    def routes = Rails.application.routes.url_helpers
  end
end
