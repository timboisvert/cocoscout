# frozen_string_literal: true

class ShowChangePlan
  # The Which dates step: the series a date is part of, what's on each date,
  # and the events tied to the chosen dates (linked to them, or in the same
  # room the same day) that the manager may want to include.
  module Dates
    module_function

    Tie = Data.define(:key, :label, :detail, :shows, :default)
    Facts = Data.define(:tickets, :buyers, :cast, :shifts, :signups) do
      def empty? = tickets.zero? && cast.zero? && shifts.zero? && signups.zero?
    end

    # The date and the ones after it in its series, still on and still to come.
    def following(show)
      return [ show ] unless show.recurring?

      show.recurrence_group.where(canceled: false).where("date_and_time >= ?", show.date_and_time)
          .includes(:production, :location).order(:date_and_time).to_a
    end

    # The whole series, in order.
    def series(show)
      return [ show ] unless show.recurring?

      show.recurrence_group.includes(:production, :location).order(:date_and_time).to_a
    end

    def past_in_series(show) = series(show).count { |s| s.date_and_time < show.date_and_time }

    # What can be chosen under "Choose dates": the production's dates still
    # to come, then the organization's other productions' in the next four
    # months.
    def choosable(show, organization)
      Show.joins(:production).where(productions: { organization_id: organization.id }, canceled: false)
          .where("date_and_time >= ?", Time.current.beginning_of_day)
          .where("shows.production_id = ? OR date_and_time <= ?", show.production_id, 4.months.from_now)
          .includes(:production, :location).order(:date_and_time).limit(400).to_a
    end

    def facts(shows)
      ids = shows.map(&:id)
      return {} if ids.empty?

      listing_ids = TicketListing.where(show_id: ids).pluck(:id, :show_id).to_h
      sold = Ticket.where(ticket_listing_id: listing_ids.keys, status: Ticket::SOLD_STATUSES).group(:ticket_listing_id).count
      buyers = TicketOrder.paid_like.where(ticket_listing_id: listing_ids.keys)
                          .group(:ticket_listing_id).distinct.count(Arel.sql("COALESCE(LOWER(buyer_email), id::text)"))
      cast = ShowPersonRoleAssignment.where(show_id: ids).group(:show_id).distinct.count(Arel.sql("assignable_type || assignable_id"))
      shifts = Shift.where(source_type: "Show", source_id: ids).group(:source_id).count
      ShiftShow.where(show_id: ids).group(:show_id).count.each { |id, n| shifts[id] = [ shifts[id].to_i, n ].max }
      instance_show = SignUpFormInstance.where(show_id: ids).pluck(:id, :show_id).to_h
      slot_instance = SignUpSlot.where(sign_up_form_instance_id: instance_show.keys).pluck(:id, :sign_up_form_instance_id).to_h
      signups = Hash.new(0)
      SignUpRegistration.active.where(sign_up_slot_id: slot_instance.keys).pluck(:sign_up_slot_id).each do |slot|
        signups[instance_show[slot_instance[slot]]] += 1
      end
      SignUpRegistration.active.where(sign_up_form_instance_id: instance_show.keys, sign_up_slot_id: nil).pluck(:sign_up_form_instance_id).each do |inst|
        signups[instance_show[inst]] += 1
      end
      by_show = listing_ids.invert
      shows.to_h do |show|
        listing = by_show[show.id]
        [ show.id, Facts.new(tickets: sold[listing].to_i, buyers: buyers[listing].to_i, cast: cast[show.id].to_i,
                             shifts: shifts[show.id].to_i, signups: signups[show.id].to_i) ]
      end
    end

    # Events tied to the chosen dates that aren't chosen: the ones linked to
    # them (chosen by default; a warm-up without its show makes no sense),
    # and other events in the same room the same day (left to the manager).
    def ties(shows, organization)
      chosen = shows.map(&:id).to_set
      linked = shows.flat_map { |s| s.event_linkage ? s.event_linkage.shows.to_a : [] }
                    .reject { |s| chosen.include?(s.id) || s.canceled? }.uniq(&:id)
      ties = []
      linked.group_by { |s| s.display_name.presence || s.production.name }.each do |name, list|
        times = list.map { |s| s.date_and_time.strftime("%-l:%M %p").strip }.uniq
        when_words = list.size == 1 ? "#{list.first.date_and_time.strftime('%a, %b %-d')} at #{times.first}" : "#{times.one? ? "#{times.first} " : ''}on each of these dates"
        ties << Tie.new(key: "linked-#{list.map(&:id).join('-')}", label: "#{name}, #{when_words}",
                        detail: "Linked to #{shows.first.display_name.presence || shows.first.production.name}.", shows: list.sort_by(&:date_and_time), default: true)
      end
      taken = chosen + linked.map(&:id)
      shows.each do |show|
        next unless show.location_id

        Show.joins(:production).where(productions: { organization_id: organization.id }, canceled: false, location_id: show.location_id)
            .where(date_and_time: show.date_and_time.all_day).where.not(id: taken.to_a)
            .includes(:production, :location_space).each do |other|
          next if show.location_space_id && other.location_space_id && other.location_space_id != show.location_space_id

          taken << other.id
          place = other.location_space&.name || other.location&.name
          ties << Tie.new(key: "night-#{other.id}", label: "#{other.display_name.presence || other.production.name}, #{other.date_and_time.strftime('%a, %b %-d at %-l:%M %p')}",
                          detail: "#{place}, the same day. Choose it if the whole day is off.", shows: [ other ], default: false)
        end
      end
      ties
    end
  end
end
