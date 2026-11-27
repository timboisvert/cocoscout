# frozen_string_literal: true

class ShowChangePlan
  # Where a move sends each date, and what's in the way there: the room, the
  # cast, and the staff (Tim, 2026-11-27). A date moves in place: the same
  # show record gets its new time, so its tickets, cast, shifts, sign-ups and
  # money go with it.
  #
  # change.move:
  #   single  { "date", "starts", "ends", "location_id", "location_space_id", "linked" }
  #   series  { "mode" => "series", "wday", "starts", "location_id", "location_space_id",
  #             "per_date" => { show_id => { "choice" => move|keep|other|cancel, "at" } } }
  #   contract { "mode" => "contract", "what" => night|show|rental, "date",
  #              "rental_starts", "rental_ends", "own_times", "show_starts", "show_ends", "location_space_id" }
  module Moves
    module_function

    Destination = Data.define(:show, :was_starts, :was_ends, :now_starts, :now_ends, :location_id, :location_space_id, :choice, :linked_to) do
      def offset = now_starts && was_starts ? now_starts - was_starts : 0
      def moves? = choice == "move" && now_starts.present? && (offset != 0 || location_changed?)
      def location_changed? = location_id.to_i != show.location_id.to_i || location_space_id.to_i != show.location_space_id.to_i
      def duration_minutes = ((now_ends - now_starts) / 60).round
    end

    Conflict = Data.define(:kind, :words, :person, :shift)

    def parse_time(date, hhmm)
      return nil if date.blank? || hhmm.blank?

      Time.zone.parse("#{date} #{hhmm}")
    rescue ArgumentError
      nil
    end

    def mode(change) = change.move["mode"].presence || (change.contract_id ? "contract" : "single")

    # Every date in the change and where it goes; the linked events chosen
    # with a date move by as much as it does.
    def destinations(change)
      move = change.move || {}
      mains = change.main_shows.reject(&:canceled?)
      list = case mode(change)
      when "series" then series_destinations(mains, move)
      when "contract" then mains.map { |show| contract_destination(show, move) }
      else mains.map { |show| single_destination(show, move) }
      end
      linked = change.also_shows.reject(&:canceled?).filter_map do |other|
        lead = list.find { |d| d.show.event_linkage_id && d.show.event_linkage_id == other.event_linkage_id && d.show.date_and_time.to_date == other.date_and_time.to_date } ||
               list.find { |d| d.show.date_and_time.to_date == other.date_and_time.to_date }
        next unless lead && lead.choice == "move"

        Destination.new(show: other, was_starts: other.date_and_time, was_ends: other.ends_at,
                        now_starts: other.date_and_time + lead.offset, now_ends: other.ends_at + lead.offset,
                        location_id: other.location_id, location_space_id: other.location_space_id, choice: "move", linked_to: lead.show.id)
      end
      list + linked
    end

    def single_destination(show, move)
      starts = parse_time(move["date"], move["starts"]) || show.date_and_time
      ends = parse_time(move["date"], move["ends"]) || (starts + (show.ends_at - show.date_and_time))
      ends += 1.day if ends <= starts
      Destination.new(show: show, was_starts: show.date_and_time, was_ends: show.ends_at, now_starts: starts, now_ends: ends,
                      location_id: (move["location_id"].presence || show.location_id)&.to_i,
                      location_space_id: move.key?("location_space_id") ? move["location_space_id"].presence&.to_i : show.location_space_id,
                      choice: "move", linked_to: nil)
    end

    # Each date to the chosen weekday on or after it, at the new time, for
    # as long as it ran.
    def series_destinations(shows, move)
      wday = move["wday"].presence&.to_i
      per = move["per_date"] || {}
      shows.map do |show|
        date = show.date_and_time.to_date
        date += (wday - date.wday) % 7 if wday
        starts = parse_time(date.iso8601, move["starts"].presence || show.date_and_time.strftime("%H:%M"))
        choice = per.dig(show.id.to_s, "choice").presence || "move"
        if choice == "other"
          at = (Time.zone.parse(per.dig(show.id.to_s, "at").to_s) rescue nil)
          starts = at || starts
          choice = "move"
        end
        length = show.ends_at - show.date_and_time
        Destination.new(show: show, was_starts: show.date_and_time, was_ends: show.ends_at,
                        now_starts: (choice == "move" ? starts : show.date_and_time),
                        now_ends: (choice == "move" ? starts + length : show.ends_at),
                        location_id: (move["location_id"].presence || show.location_id)&.to_i,
                        location_space_id: move.key?("location_space_id") ? move["location_space_id"].presence&.to_i : show.location_space_id,
                        choice: choice, linked_to: nil)
      end
    end

    # A contract date: the show's own new times, worked out from the night
    # (ContractTimes has the rental's).
    def contract_destination(show, move)
      times = contract_times(show, move)
      Destination.new(show: show, was_starts: show.date_and_time, was_ends: show.ends_at,
                      now_starts: times[:show_starts], now_ends: times[:show_ends],
                      location_id: show.location_id, location_space_id: (move["location_space_id"].presence || show.location_space_id)&.to_i,
                      choice: "move", linked_to: nil)
    end

    # The rental's and the show's times after a contract move. The whole
    # night: everything moves by the same amount, unless the manager set the
    # show's times. Only the show: same rental, new show times. Only the
    # rental: new rental times, the show keeps its own.
    def contract_times(show, move)
      rental = show.space_rental
      was = { rental_starts: rental.starts_at, rental_ends: rental.ends_at,
              show_starts: rental.effective_event_starts_at, show_ends: rental.effective_event_ends_at }
      date = move["date"].presence || rental.starts_at.to_date.iso8601
      what = move["what"].presence || "night"
      rental_starts = parse_time(date, move["rental_starts"]) || was[:rental_starts]
      rental_ends = parse_time(date, move["rental_ends"]) || (rental_starts + (was[:rental_ends] - was[:rental_starts]))
      rental_ends += 1.day if rental_ends <= rental_starts
      own = ActiveModel::Type::Boolean.new.cast(move["own_times"])
      case what
      when "show"
        rental_starts, rental_ends = was[:rental_starts], was[:rental_ends]
        date = rental_starts.to_date.iso8601
        show_starts = parse_time(date, move["show_starts"]) || was[:show_starts]
        show_ends = parse_time(date, move["show_ends"]) || was[:show_ends]
      when "rental"
        show_starts, show_ends = was[:show_starts], was[:show_ends]
      else
        if own && move["show_starts"].present?
          show_starts = parse_time(date, move["show_starts"])
          show_ends = parse_time(date, move["show_ends"]) || (show_starts + (was[:show_ends] - was[:show_starts]))
        else
          offset = rental_starts - was[:rental_starts]
          show_starts = was[:show_starts] + offset
          show_ends = was[:show_ends] + offset
        end
      end
      show_ends += 1.day if show_ends && show_starts && show_ends <= show_starts
      { rental_starts: rental_starts, rental_ends: rental_ends, show_starts: show_starts, show_ends: show_ends, what: what,
        own: own || what == "show" || rental.event_starts_at.present?, was: was }
    end

    # The show's times must sit inside the rental.
    def contract_error(show, move)
      t = contract_times(show, move)
      return "The show has to start and end inside the rental." if t[:show_starts] < t[:rental_starts] || t[:show_ends] > t[:rental_ends]

      nil
    end

    # ---- What's in the way --------------------------------------------------

    BUFFER = 1.minute

    def overlaps?(a_start, a_end, b_start, b_end)
      a_start < (b_end - BUFFER) && a_end > (b_start + BUFFER)
    end

    # Another event or booking in the same room at the new time.
    def room_conflicts(dest, change)
      return [] unless dest.location_id

      moving = change.all_show_ids
      list = []
      Show.joins(:production).where(productions: { organization_id: change.organization_id }, canceled: false, location_id: dest.location_id)
          .where(date_and_time: (dest.now_starts - 1.day)..dest.now_ends).where.not(id: moving)
          .includes(:production, :location_space).each do |other|
        next if dest.location_space_id && other.location_space_id && other.location_space_id != dest.location_space_id
        next if other.space_rental_id && other.space_rental_id == dest.show.space_rental_id
        next unless overlaps?(dest.now_starts, dest.now_ends, other.date_and_time, other.ends_at)

        place = other.location_space&.name || other.location&.name
        list << Conflict.new(kind: :room, person: nil, shift: nil,
                             words: "#{place} is booked: #{other.display_name.presence || other.production.name}, #{time_range(other.date_and_time, other.ends_at)}")
      end
      SpaceRental.joins(:contract).where(location_id: dest.location_id).where.not(contracts: { status: "cancelled" })
                 .where.not(id: dest.show.space_rental_id)
                 .where("space_rentals.starts_at < ? AND space_rentals.ends_at > ?", dest.now_ends - BUFFER, dest.now_starts + BUFFER)
                 .includes(:contract, :location_space).each do |rental|
        next if dest.location_space_id && rental.location_space_id && rental.location_space_id != dest.location_space_id

        name = rental.contract.production_name.presence || rental.contract.contractor_name.presence || "a private event"
        list << Conflict.new(kind: :room, person: nil, shift: nil,
                             words: "#{rental.location_space&.name || 'The room'} is booked: #{name}, #{time_range(rental.starts_at, rental.ends_at)}")
      end
      list.uniq(&:words)
    end

    # Cast members who are in another event at the new time.
    def cast_conflicts(dest, change)
      moving = change.all_show_ids
      people = ShowChanges.cast_entries(dest.show).map { |e| e["person_id"] }
      return [] if people.empty?

      groups = GroupMembership.where(person_id: people).pluck(:group_id, :person_id)
      others = Show.joins(:production).where(productions: { organization_id: change.organization_id }, canceled: false)
                   .where(date_and_time: (dest.now_starts - 1.day)..dest.now_ends).where.not(id: moving)
                   .includes(:production).select { |s| overlaps?(dest.now_starts, dest.now_ends, s.date_and_time, s.ends_at) }
      return [] if others.empty?

      by_show = others.index_by(&:id)
      found = {}
      ShowPersonRoleAssignment.where(show_id: by_show.keys).each do |a|
        ids = if a.assignable_type == "Person" then [ a.assignable_id ]
        else groups.select { |g, _| g == a.assignable_id }.map(&:last)
        end
        (ids & people).each { |pid| found[pid] ||= by_show[a.show_id] }
      end
      records = Person.where(id: found.keys).index_by(&:id)
      found.filter_map do |pid, other|
        person = records[pid]
        next unless person

        Conflict.new(kind: :cast, person: person, shift: nil,
                     words: "#{person.name} is cast in #{other.display_name.presence || other.production.name} at #{other.date_and_time.strftime('%-l:%M %p').strip} that day")
      end
    end

    # Staff on the shifts that move, who are on another shift at the new
    # time or said they can't work then.
    def staff_conflicts(dest, change, lines)
      offset = dest.offset
      return [] if offset.zero?

      moving_shift_ids = lines.map { |l| l.shift.id }
      people = lines.filter_map(&:person).uniq
      return [] if people.empty?

      from = lines.map { |l| l.shift.starts_at + offset }.min
      to = lines.map { |l| l.shift.ends_at + offset }.max
      resolver = (StaffAvailabilityResolver.new(people.map(&:id), from: from.to_date, to: to.to_date) rescue nil)
      lines.filter_map do |line|
        next unless line.person

        starts = line.shift.starts_at + offset
        ends = line.shift.ends_at + offset
        other = ShiftAssignment.active.joins(:shift).where(person_id: line.person.id)
                               .where.not(shift_id: moving_shift_ids)
                               .where("shifts.starts_at < ? AND shifts.ends_at > ?", ends - BUFFER, starts + BUFFER)
                               .includes(shift: [ :house_role, :source ]).first
        if other
          what = other.shift.source.is_a?(::Show) ? " at #{other.shift.source.display_name.presence || other.shift.source.production.name}" : ""
          next Conflict.new(kind: :staff, person: line.person, shift: line.shift,
                            words: "#{line.person.name} is already on #{other.shift.role_label}#{what}, #{other.shift.starts_at.strftime('%-l:%M %p').strip}")
        end
        verdict = resolver&.verdict(line.person.id, starts, ends)
        next unless verdict.respond_to?(:blocked?) && verdict.blocked?

        Conflict.new(kind: :staff, person: line.person, shift: line.shift,
                     words: "#{line.person.name} marked #{starts.strftime('%A, %B %-d')} as unavailable at that time")
      end
    end

    def time_range(from, to) = "#{from.strftime('%-l:%M').strip} to #{to.strftime('%-l:%M %p').strip}"
  end
end
