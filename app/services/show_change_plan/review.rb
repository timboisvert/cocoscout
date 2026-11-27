# frozen_string_literal: true

class ShowChangePlan
  # The Review step: everything that will happen, in plain sentences that
  # follow the manager's choices, every message that will go, and the steps
  # the record page will tick off (Tim, 2026-11-27).
  class Review
    Message = Data.define(:who, :how, :count, :subject, :body)

    attr_reader :change, :plan, :dests, :previews

    # previews: the cast and staff notices built before the change
    # (ShowChangeNotices), whose drafts are the words when none were edited.
    def initialize(change, plan, dests: nil, previews: nil)
      @change = change
      @plan = plan
      @dests = dests || (change.move? ? Moves.destinations(change) : [])
      @previews = previews
    end

    # The edited words for a send, or its draft as the notices would write it.
    def notice_words(prefix, section_key)
      section = previews&.section(section_key)
      draft = section ? previews.draft(section) : {}
      [ change.choice("#{prefix}_subject").presence || draft[:subject], change.choice("#{prefix}_body").presence || draft[:body] ]
    end

    def titled(text) = text.to_s.gsub("{{show_title}}", plan.acting_shows.map { |s| s.display_name.presence || s.production.name }.uniq.to_sentence)

    def h = ActionController::Base.helpers
    def money(cents) = BuyerWords.money(cents)
    def day(t) = t.strftime("%b %-d")
    def day_time(t) = "#{t.strftime('%a, %b %-d')}, #{t.strftime('%-l:%M %p').strip}"
    def people(n, word = "person", plural = "people") = "#{n} #{n == 1 ? word : plural}"
    def on?(key, default: true) = change.on?(key, default: default)

    def dates_words(shows)
      shows = shows.sort_by(&:date_and_time)
      by_production = shows.group_by(&:production)
      by_production.map { |production, list| "#{production.name} on #{list.map { |s| day(s.date_and_time) }.to_sentence}" }.to_sentence
    end

    def headline
      n = plan.acting_shows.size
      case change.kind
      when "cancel" then "Ready to cancel #{n == 1 ? 'the date' : "#{n} dates"}"
      when "restore" then "Ready to bring back #{n == 1 ? 'the date' : "#{n} dates"}"
      else
        moving = dests.select(&:moves?)
        moving.size == 1 ? "Ready to move it to #{day_time(moving.first.now_starts)}" : "Ready to move #{moving.size} dates"
      end
    end

    def button
      n = plan.acting_shows.size
      case change.kind
      when "cancel" then "Cancel #{n == 1 ? 'the date' : "#{n} dates"}"
      when "restore" then "Bring back #{n == 1 ? 'the date' : "#{n} dates"}"
      else dests.count(&:moves?) == 1 ? "Move the date" : "Move #{dests.count(&:moves?)} dates"
      end
    end

    # What the manager should know before confirming a move: a room that's
    # already booked at the new time. CocoScout doesn't stop it (two events
    # can share a room on purpose), but it never passes unsaid.
    def warnings
      return [] unless change.move?

      dests.select(&:moves?).reject(&:linked_to).flat_map do |dest|
        probe = change.contract_id ? dest.with(now_starts: Moves.contract_times(dest.show, change.move)[:rental_starts], now_ends: Moves.contract_times(dest.show, change.move)[:rental_ends]) : dest
        Moves.room_conflicts(probe, change).map { |c| "#{day(dest.now_starts)}: #{c.words}." }
      end.uniq
    end

    def sentences
      case change.kind
      when "cancel" then cancel_sentences
      when "restore" then restore_sentences
      else move_sentences
      end
    end

    def cancel_sentences
      list = []
      mains = change.main_shows.reject(&:canceled?)
      also = change.also_shows.reject(&:canceled?)
      line = "Cancel #{dates_words(mains)}"
      line += also.any? ? ", and #{also.size == 1 ? 'the event' : "the #{also.size} events"} tied to #{mains.one? ? 'it' : 'them'} (#{also.map { |s| s.display_name.presence || s.production.name }.uniq.to_sentence})." : "."
      list << line
      list << "Stop ticket sales on #{plan.acting_shows.size == 1 ? 'the date' : 'those dates'}." if plan.listings.any?
      b = plan.buyers
      if b.card.any?
        if change.choice(:buyers_action) == "rebook"
          target = TicketListing.find_by(id: change.choice(:rebook_listing_id))
          list << "Move #{b.buyer_count == 1 ? "1 buyer's" : "#{b.buyer_count} buyers'"} tickets to #{target ? day_time(target.show.date_and_time) : 'the date you chose'}, and email #{b.buyer_count == 1 ? 'them' : 'each of them'}."
        else
          list << "Refund #{people(b.buyer_count(b.card), 'buyer', 'buyers')} #{money(b.card_cents)}, tax and fees included, and email #{b.buyer_count(b.card) == 1 ? 'them' : 'each of them'}."
        end
      end
      if b.other.any?
        list << (on?(:other_paid) ? "Mark #{b.other.size} #{b.other.size == 1 ? 'order' : 'orders'} paid another way (#{money(b.other_cents)}) as refunded, and email #{b.other.size == 1 ? 'that buyer' : 'those buyers'}." : "Leave the #{b.other.size} #{b.other.size == 1 ? 'order' : 'orders'} paid another way as they are.")
      end
      list << "Return pass credits to #{people(b.buyer_count(b.pass), 'pass holder', 'pass holders')}, and email them." if b.pass.any?
      if b.comps.any? || b.comp_requests.any?
        parts = []
        parts << "#{on?(:comps_email) ? 'Email' : 'Cancel the tickets of'} the #{people(b.buyer_count(b.comps), 'comp holder', 'comp holders')}" if b.comps.any?
        parts << "close #{b.comp_requests.map { |r| "#{r.requested_by.person&.name || r.requested_by.email_address}'s comp request" }.to_sentence}, notifying #{b.comp_requests.size == 1 ? 'them' : 'each of them'}" if b.comp_requests.any?
        list << "#{parts.join(', and ').upcase_first}."
      end
      c = plan.cast
      if c.people.any? || c.vacancies.any?
        parts = []
        parts << (on?(:cast_notify) ? "Notify the #{people(c.people.size, 'cast member', 'cast members')} of their canceled dates" : "Don't notify the cast") if c.people.any?
        parts << "close #{c.vacancies.size} \"can't make it\" #{c.vacancies.size == 1 ? 'request' : 'requests'}#{c.invited_count.positive? ? " and notify the #{people(c.invited_count)} invited to cover" : ''}" if c.vacancies.any?
        parts << "take the dates off #{c.table_events.map { |e| e.casting_table.name }.uniq.to_sentence}" if c.table_events.any?
        list << "#{parts.join(', ').upcase_first}."
      end
      s = plan.staff
      if s.any?
        n = s.changing_shifts.size
        stay = s.staying.filter_map(&:person).uniq
        line = on?(:shifts_off) ? "Take #{n} #{n == 1 ? 'shift' : 'shifts'} off the schedule" : "Leave the #{n} #{n == 1 ? 'shift' : 'shifts'} on the schedule"
        line += ", close #{s.vacancies.size} cover #{s.vacancies.size == 1 ? 'request' : 'requests'}" if on?(:shifts_off) && s.vacancies.any?
        line += on?(:staff_notify) && s.people.any? ? ", and notify #{s.people.map(&:name).to_sentence}." : "."
        line += " #{stay.map(&:name).to_sentence} #{stay.one? ? 'stays' : 'stay'} on: #{stay.one? ? 'that shift' : 'those shifts'} also #{stay.one? ? 'covers' : 'cover'} an event that isn't canceled." if stay.any?
        list << line if n.positive? || stay.any?
      end
      if plan.signups.registrations.any?
        n = plan.signups.registrations.size
        list << (on?(:signups_cancel) ? "Cancel #{n} #{n == 1 ? 'registration' : 'registrations'}, notify those people, and close the sign-up for these dates." : "Close the sign-up for these dates, and leave the #{n} registrations as they are.")
      end
      list << (on?(:students_email) ? "Email the #{people(plan.students.size, 'student', 'students')} that #{plan.acting_shows.size == 1 ? 'the class is' : 'the classes are'} canceled." : "Don't email the students.") if plan.students.any?
      m = plan.money
      parts = []
      parts << "clear the unpaid pay for #{m.payouts.size == 1 ? day(m.payouts.first.show.date_and_time) : "#{m.payouts.size} dates"}" if m.payouts.any? && on?(:clear_pay)
      parts << "spread #{m.expenses.map(&:name).to_sentence} over the dates still on" if m.expenses.any? && on?(:respread)
      parts << "take #{m.contract_payments.size} pending contract #{m.contract_payments.size == 1 ? 'payment' : 'payments'} off" if m.contract_payments.any?
      parts << "let the room go on #{plan.rentals_to_release.map { |r| day(r.starts_at) }.to_sentence}" if plan.rentals_to_release.any?
      parts << "take the dates out of #{plan.follower_drafts.size == 1 ? 'your draft follower email' : 'your draft follower emails'}" if plan.follower_drafts.any? && on?(:followers)
      list << "#{parts.to_sentence.upcase_first}." if parts.any?
      list
    end

    def move_sentences
      list = []
      moving = dests.select(&:moves?)
      place_only = moving.any? && moving.all? { |d| d.offset.zero? }
      what_new = place_only ? "new place" : "new date"
      kept = dests.select { |d| d.choice == "keep" }
      canceling = dests.select { |d| d.choice == "cancel" }
      moving.reject(&:linked_to).each do |d|
        place = d.location_changed? ? " in #{Location.find_by(id: d.location_id)&.name}#{d.location_space_id ? ", #{LocationSpace.find_by(id: d.location_space_id)&.name}" : ''}" : ""
        list << "Move #{d.show.display_name.presence || d.show.production.name} from #{day_time(d.was_starts)} to #{day_time(d.now_starts)}#{place}."
      end
      linked = moving.select(&:linked_to)
      list << "Move #{linked.map { |d| d.show.display_name.presence || d.show.production.name }.uniq.to_sentence} with #{moving.reject(&:linked_to).one? ? 'it' : 'them'}, by as much." if linked.any?
      list << "Keep #{kept.map { |d| day(d.was_starts) }.to_sentence} where #{kept.one? ? 'it is' : 'they are'}." if kept.any?
      list << "Leave #{canceling.map { |d| day(d.was_starts) }.to_sentence} on the old day for now; the change's page offers to cancel #{canceling.one? ? 'it' : 'them'} next." if canceling.any?
      if plan.listings.any?
        b = plan.buyers
        list << (on?(:buyers_email) ? "Email #{people(b.buyer_count, 'buyer', 'buyers')} the #{place_only ? 'new place' : 'new date and time'}." : "Don't email the buyers. Their tickets work #{place_only ? 'at the new place' : 'at the new time'}.")
      end
      cast = plan.cast.people
      if cast.any?
        opened = (change.choice(:cast_conflicts) || {}).select { |_, v| v == "open" }.keys.map(&:to_i)
        names = cast.select { |c| opened.include?(c.person.id) }.map { |c| c.person.name }
        line = on?(:cast_notify) ? "Notify #{people(cast.size - names.size, 'cast member', 'cast members')} of the #{what_new}" : "Don't notify the cast"
        line += ", and open #{names.map { |n| "#{n}'s role" }.to_sentence} for cover, notifying #{names.one? ? names.first : 'each of them'}" if names.any?
        list << "#{line}."
      end
      s = plan.staff
      if s.any?
        opened = (change.choice(:staff_conflicts) || {}).select { |_, v| v == "open" }.keys
        n = s.changing_shifts.size
        tell = change.contract_id ? on?(:shifts_move) : on?(:staff_notify)
        line = if place_only then tell ? "Notify the staff of the new place" : "Don't notify the staff"
        else "#{on?(:shifts_move) ? "Move #{n} #{n == 1 ? 'shift' : 'shifts'} with the date" : 'Leave the shifts where they are'}#{tell ? ' and notify the staff' : ''}"
        end
        line += ", opening #{opened.size} for cover" if opened.any?
        list << "#{line}."
        stay = s.staying.filter_map(&:person).uniq
        list << "#{stay.map(&:name).to_sentence} #{stay.one? ? 'stays' : 'stay'} on the old time: #{stay.one? ? 'that shift' : 'those shifts'} also #{stay.one? ? 'covers' : 'cover'} an event that isn't moving." if stay.any?
        added = (change.choice(:add_shifts) || {}).count { |_, v| ActiveModel::Type::Boolean.new.cast(v) }
        list << "Add #{added} #{added == 1 ? 'shift' : 'shifts'} at the new time, open for cover." if added.positive?
      end
      if plan.signups.registrations.any?
        n = plan.signups.registrations.size
        list << (change.choice(:signups_action) == "reopen" ? "Cancel the #{n} registrations and reopen every slot" : "Move the #{n} #{n == 1 ? 'registration' : 'registrations'} with the date, everyone keeping their place") +
                (on?(:signups_notify) ? ", and notify those people." : ".")
      end
      list << (on?(:students_email) ? "Email the students the new time." : "Don't email the students.") if plan.class_offerings.any?
      if change.contract_id
        rental_staff = contract_rental_staff
        if rental_staff.positive? && plan.staff.changing_shifts.empty?
          list << (on?(:shifts_move) ? "Move the #{rental_staff == 1 ? 'shift' : "#{rental_staff} shifts"} made for the rental with it, and notify the staff." : "Leave the shifts made for the rental where they are.")
        end
        list << "Notify the other people on the contract." if on?(:contract_notify)
        list << "Close #{change.contract_date_request.requested_by.person&.name || 'the'}'s request as done, and notify them." if change.contract_date_request
      end
      list
    end

    def restore_sentences
      list = [ "Bring back #{dates_words(plan.acting_shows)}." ]
      list << "Reopen ticket sales on the same ticket types. The refunds stand." if plan.listings.any?
      list << "Email the #{people(plan.refunded_orders.map(&:buyer_email).compact.uniq.size, 'refunded buyer', 'refunded buyers')} that it's back on, with a link to buy again." if on?(:buyers_email, default: false) && plan.refunded_orders.any?
      list << "Notify the #{people(plan.cast.people.size, 'cast member', 'cast members')} that it's back on." if on?(:cast_notify) && plan.cast.people.any?
      list << "Put the staff back on their shifts and notify them; a shift whose person has since taken another that overlaps opens for cover." if on?(:staff_back) && change.restores&.undo&.dig("shifts").present?
      list
    end

    # Shifts made for a contract date's rental (setup, strike), with people on them.
    def contract_rental_staff
      rental_id = change.main_shows.first&.space_rental_id
      return 0 unless rental_id

      Shift.where(source_type: "SpaceRental", source_id: rental_id).joins(:shift_assignments).merge(ShiftAssignment.active).distinct.count
    end

    # What people will receive, one row per kind of message.
    def messages
      rows = []
      case change.kind
      when "cancel"
        b = plan.buyers
        draft = BuyerWords.draft(:cancel)
        count = b.emailable.reject { |o| (o.kind == :other && !on?(:other_paid)) || (o.kind == :comp && !on?(:comps_email)) }.map(&:email).uniq.size
        rows << Message.new(who: "Ticket buyers", how: "email", count: count, subject: titled(change.choice(:buyers_subject).presence || draft[:subject]), body: change.choice(:buyers_body).presence || draft[:body]) if count.positive?
        rows << Message.new(who: "Cast", how: "notification and email", count: plan.cast.people.count(&:reachable?), subject: notice_words(:cast, "cast_off").first, body: notice_words(:cast, "cast_off").last) if on?(:cast_notify) && plan.cast.people.any?
        rows << Message.new(who: "Staff", how: "email and notification", count: plan.staff.people.size, subject: notice_words(:staff, "staff_off").first, body: notice_words(:staff, "staff_off").last) if on?(:staff_notify) && plan.staff.people.any?
        rows << Message.new(who: "People invited to cover", how: "notification", count: plan.cast.invited_count, subject: "Cover is no longer needed", body: nil) if plan.cast.invited_count.positive?
        rows << Message.new(who: "Sign-ups", how: "notification, or email for those without a login", count: plan.signups.registrations.size, subject: "Your sign-up is canceled", body: nil) if on?(:signups_cancel) && plan.signups.registrations.any?
        rows << Message.new(who: "Students", how: "email", count: plan.students.size, subject: change.choice(:students_subject).presence || CourseSessionCancellation.default_email.first, body: nil) if on?(:students_email) && plan.students.any?
      when "move"
        b = plan.buyers
        draft = BuyerWords.draft(:move)
        rows << Message.new(who: "Ticket buyers", how: "email", count: b.emailable.map(&:email).uniq.size, subject: titled(change.choice(:buyers_subject).presence || draft[:subject]), body: change.choice(:buyers_body).presence || draft[:body]) if on?(:buyers_email) && b.emailable.any?
        rows << Message.new(who: "Cast", how: "notification and email", count: plan.cast.people.count(&:reachable?), subject: notice_words(:cast, "cast_moved").first, body: notice_words(:cast, "cast_moved").last) if on?(:cast_notify) && plan.cast.people.any?
        rows << Message.new(who: "Staff", how: "email and notification", count: plan.staff.people.size, subject: notice_words(:staff, "staff_moved").first, body: notice_words(:staff, "staff_moved").last) if on?(:staff_notify) && plan.staff.people.any?
        rows << Message.new(who: "Sign-ups", how: "notification, or email for those without a login", count: plan.signups.registrations.size, subject: "Your slot has a new time", body: nil) if on?(:signups_notify) && plan.signups.registrations.any?
      when "restore"
        draft = BuyerWords.draft(:back_on)
        rows << Message.new(who: "Refunded ticket buyers", how: "email", count: plan.refunded_orders.map(&:buyer_email).compact.uniq.size, subject: titled(change.choice(:back_on_subject).presence || draft[:subject]), body: change.choice(:back_on_body).presence || draft[:body]) if on?(:buyers_email, default: false) && plan.refunded_orders.any?
        rows << Message.new(who: "Cast", how: "notification and email", count: plan.cast.people.count(&:reachable?), subject: "Back on", body: nil) if on?(:cast_notify) && plan.cast.people.any?
      end
      rows
    end

    # The steps the record page will show, in order, before they start.
    def planned_steps
      keys = case change.kind
      when "cancel"
        b = plan.buyers
        k = [ %w[dates Canceling the dates] ]
        k << (change.choice(:buyers_action) == "rebook" ? %w[rebook Moving the buyers' tickets] : %w[refunds Refunding the buyers]) if b.card.any?
        k << %w[other_paid Orders paid another way] if b.other.any? || b.pass.any?
        k << %w[comps Comp holders] if b.comps.any? || b.comp_requests.any?
        k << %w[cast Notifying the cast] if plan.cast.any?
        k << %w[staff The staff and their shifts] if plan.staff.any?
        k << %w[signups Sign-ups] if plan.signups.registrations.any?
        k << %w[students Students] if plan.students.any?
        k << %w[money Money and follower emails] if plan.money.payouts.any? || plan.money.expenses.any? || plan.follower_drafts.any?
        k
      when "restore"
        k = [ %w[dates Bringing the dates back] ]
        k << %w[buyers Emailing refunded buyers] if on?(:buyers_email, default: false) && plan.refunded_orders.any?
        k << %w[cast Notifying the cast] if on?(:cast_notify) && plan.cast.people.any?
        k << %w[staff The staff and their shifts] if on?(:staff_back) && change.restores&.undo&.dig("shifts").present?
        k
      else
        k = [ %w[dates Moving the dates] ]
        k << %w[buyers Emailing the buyers] if plan.listings.any? && on?(:buyers_email)
        k << %w[cast Notifying the cast] if plan.cast.people.any?
        k << %w[staff The staff and their shifts] if plan.staff.any? || (change.contract_id && contract_rental_staff.positive?)
        k << %w[signups Sign-ups] if plan.signups.registrations.any? || plan.signups.instances.any?
        k << %w[students Students] if plan.class_offerings.any? && on?(:students_email)
        k
      end
      keys.map { |key, *label| { "key" => key, "label" => label.join(" "), "status" => "pending" } }
    end
  end
end
