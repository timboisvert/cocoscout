# frozen_string_literal: true

class ShowChangePlan
  class Apply
    # Moving dates (Tim, 2026-11-27): each date moves in place, its linked
    # events with it; then the buyers, cast, staff, sign-ups and students
    # are dealt with the way the manager chose on What it touches.
    class MoveRun
      delegate :change, :plan, :by, :organization, :step, :words, :notices, :notice_words, :deliver_person,
               :first_name, :day, :day_time, :open_roles_for_cover!, to: :@apply

      def initialize(apply)
        @apply = apply
      end

      def run
        dests = Moves.destinations(change)
        moving = dests.select(&:moves?)
        @was = moving.to_h { |d| [ d.show.id, d.was_starts ] }
        staff = plan.staff
        open_before = staff.open_shifts.map { |l| [ l.shift, l.shift.starts_at ] }
        staying = staff.staying
        conflicts = choices_hash(:cast_conflicts)
        staff_conflicts = choices_hash(:staff_conflicts)
        signups = plan.signups

        step(:dates, moving.size == 1 ? "Moved to #{day_time(moving.first.now_starts)}" : "#{moving.size} dates moved") do
          move_dates!(dests, moving)
        end

        buyers!(moving) if plan.listings.any?
        cast!(moving, conflicts) if plan.cast.people.any?
        staff!(moving, staff, staff_conflicts, open_before, staying) if staff.any?
        signups!(signups) if signups.registrations.any? || signups.instances.any?
        students! if plan.class_offerings.any?
      end

      def choices_hash(key)
        value = change.choice(key) || {}
        value.is_a?(Hash) ? value : {}
      end

      def move_dates!(dests, moving)
        if Moves.mode(change) == "contract"
          move_contract_date!
        else
          moving.each do |dest|
            show = dest.show
            show.date_and_time = dest.now_starts
            show.duration_minutes = dest.duration_minutes
            show.location_id = dest.location_id if dest.location_id
            show.location_space_id = dest.location_space_id
            show.save!
          rescue ActiveRecord::RecordInvalid => e
            change.add_problem!(key: "move-#{show.id}", kind: "show", label: "#{show.production.name}, #{day_time(dest.was_starts)} couldn't move.",
                                detail: e.record.errors.full_messages.to_sentence)
          end
        end
        kept = dests.select { |d| d.choice == "keep" }
        canceling = dests.select { |d| d.choice == "cancel" }
        change.update_columns(summary: change.summary.merge("kept_ids" => kept.map { |d| d.show.id }, "to_cancel_ids" => canceling.map { |d| d.show.id }))
        parts = [ moving.size == 1 ? "Moved to #{day_time(moving.first.now_starts)}" : "#{moving.size} dates moved" ]
        parts << "#{kept.size} kept where #{kept.one? ? 'it was' : 'they were'}" if kept.any?
        parts << "#{canceling.size} still to cancel" if canceling.any?
        parts.join("; ")
      end

      # A contract date: the night moves through the contract, so its room,
      # services and payments move with it, then its show.
      def move_contract_date!
        show = change.main_shows.first
        rental = show.space_rental
        times = Moves.contract_times(show, change.move)
        if change.move["location_space_id"].present? && change.move["location_space_id"].to_i != rental.location_space_id.to_i
          ContractDateChanges.change_space!(contract: rental.contract, rental: rental, location_space_id: change.move["location_space_id"])
          rental.reload
        end
        own = times[:show_starts] != times[:rental_starts] || times[:show_ends] != times[:rental_ends]
        ContractDateChanges.retime!(contract: rental.contract, rental: rental, starts_at: times[:rental_starts], ends_at: times[:rental_ends],
                                    event_starts_at: (times[:show_starts] if own), event_ends_at: (times[:show_ends] if own))
        rental.contract.refresh_dates_from_rentals! if rental.contract.respond_to?(:refresh_dates_from_rentals!)
        notify_contract_people!(show, times) if change.on?(:contract_notify)
      end

      def notify_contract_people!(show, times)
        contract = show.space_rental&.contract
        return unless contract

        people = contract_people(contract)
        people.each do |person|
          deliver_person("date_change_contract_moved", person, {
            recipient_name: first_name(person), organization_name: organization.name,
            production_name: contract.production_name.presence || show.production.name,
            was: day_time(times[:was][:rental_starts]), now: day_time(times[:rental_starts]),
            contracts_url: Rails.application.routes.url_helpers.my_contracts_url(**TicketOrderMailer.url_options)
          })
        end
      end

      def contract_people(contract)
        ids = []
        ids += contract.contract_people.pluck(:person_id) if contract.respond_to?(:contract_people)
        requester = change.contract_date_request&.requested_by&.person
        Person.where(id: ids.uniq).where.not(id: requester&.id).includes(:user).to_a
      end

      def buyers!(moving)
        return unless change.on?(:buyers_email)

        step(:buyers, "Buyers emailed the new date and time") do
          subject, body = words(:buyers, :move)
          offer = change.on?(:buyers_refund_offer)
          orders = []
          moving.each do |dest|
            listing = TicketListing.find_by(show_id: dest.show.id)
            next unless listing

            orders.concat(TicketShowChange.orders(listing).to_a)
          end
          groups = orders.group_by { |o| o.buyer_email.to_s.strip.downcase }
          groups.each_value do |list|
            variables = BuyerWords.moved_variables(change, list, was_by_show: @was, offer_refund: offer)
            TicketOrderMailer.date_change(list.first, subject: subject, body: body, variables: variables).deliver_later
          end
          orders.group_by(&:ticket_listing).each { |listing, list| TicketShowChange.mark_told!(listing, TicketOrder.where(id: list.map(&:id))) }
          "#{groups.size} #{groups.size == 1 ? 'buyer' : 'buyers'} emailed#{offer ? ', with a refund link' : ''}"
        end
      end

      def cast!(moving, conflicts)
        step(:cast, "Cast notified of the new date") do
          opened = []
          conflicts.each do |person_id, choice|
            next unless choice == "open"

            person = Person.find_by(id: person_id)
            next unless person

            moving.each do |dest|
              roles = open_roles_for_cover!(dest.show, person)
              next if roles.empty?

              opened << person.id
              deliver_person("date_change_role_opened", person, {
                recipient_name: first_name(person), organization_name: organization.name, production_name: dest.show.production.name,
                role_name: roles.compact.to_sentence, was: day_time(dest.was_starts), now: day_time(dest.now_starts),
                reason: change.choice("cast_conflict_reason_#{person.id}").presence || "That clashes with something else you're on"
              }, show: dest.show)
            end
          end
          told = 0
          if change.on?(:cast_notify)
            list = notices
            section = list.section("cast_moved")
            if section
              subject, body = notice_words(list, section, :cast)
              ids = section.reachable.map { |r| r.person.id } - opened
              told = list.send!("cast_moved", person_ids: ids, subject: subject, body: body, sender: by) if ids.any?
            end
          end
          parts = [ change.on?(:cast_notify) ? "#{told} cast notified" : "The cast weren't notified" ]
          parts << "#{opened.uniq.size} #{opened.uniq.size == 1 ? 'role' : 'roles'} opened for cover" if opened.any?
          parts.join("; ")
        end
      end

      def staff!(moving, staff, conflicts, open_before, staying)
        move_shifts = change.on?(:shifts_move)
        tell = change.on?(:staff_notify)
        step(:staff, "Shifts moved; staff notified") do
          opened = []
          conflicts.each do |assignment_key, choice|
            next unless choice == "open"

            shift_id, person_id = assignment_key.to_s.split("-").map(&:to_i)
            assignment = ShiftAssignment.active.find_by(shift_id: shift_id, person_id: person_id)
            next unless assignment

            shift = assignment.shift
            was = shift.starts_at
            assignment.decline!(reason: "The date moved, and the new time clashes with another shift.")
            dest = moving.find { |d| shift.covered_shows.map(&:id).include?(d.show.id) } || moving.first
            opened << person_id
            deliver_person("date_change_shift_opened", assignment.person, {
              recipient_name: first_name(assignment.person), organization_name: organization.name, production_name: dest&.show&.production&.name.to_s,
              shift: "#{shift.role_label}, #{day_time(was)}", now: day_time(was + dest.offset),
              clash: change.choice("staff_conflict_reason_#{assignment_key}").presence || "other shift"
            })
          end

          list = notices
          section = list.section("staff_moved")
          told = 0
          if section
            ids = section.reachable.map { |r| r.person.id } - opened
            if tell && ids.any?
              subject, body = notice_words(list, section, :staff)
              told = list.send!("staff_moved", person_ids: ids, subject: subject, body: body, sender: by, shift_action: move_shifts)
            elsif move_shifts
              list.move_shifts!(section)
            end
          end
          moved_open = 0
          if move_shifts
            open_before.each do |shift, starts|
              shift.reload
              dest = moving.find { |d| shift.covered_shows.map(&:id).include?(d.show.id) }
              next unless dest && shift.starts_at.to_i == starts.to_i

              shift.update!(starts_at: shift.starts_at + dest.offset, ends_at: shift.ends_at + dest.offset)
              moved_open += 1
            end
          end
          added = add_shifts!(moving, staying)
          parts = [ move_shifts ? "#{staff.changing_shifts.size} #{staff.changing_shifts.size == 1 ? 'shift' : 'shifts'} moved with the date" : "The shifts stayed where they were" ]
          parts << "#{told} on staff notified" if tell
          parts << "#{opened.size} #{opened.size == 1 ? 'shift' : 'shifts'} opened for cover" if opened.any?
          parts << "#{added} #{added == 1 ? 'shift' : 'shifts'} added at the new time, open for cover" if added.positive?
          parts.join("; ")
        end
      end

      # A shift that stays (it covers another event too) can be matched at
      # the new time with an empty one of the same role, open for cover.
      def add_shifts!(moving, staying)
        wanted = choices_hash(:add_shifts).select { |_, v| ActiveModel::Type::Boolean.new.cast(v) }.keys.map(&:to_i)
        return 0 if wanted.empty?

        staying.map(&:shift).uniq.select { |s| wanted.include?(s.id) }.sum do |shift|
          dest = moving.find { |d| (plan.tied_shifts(d.show).map(&:id)).include?(shift.id) } || moving.first
          next 0 unless dest

          Shift.create!(organization: organization, house_role: shift.house_role, source: dest.show,
                        starts_at: shift.starts_at + dest.offset, ends_at: shift.ends_at + dest.offset,
                        required_count: shift.required_count, coverage_mode: :needs_assignment)
          1
        end
      end

      def signups!(signups)
        reopen = change.choice(:signups_action) == "reopen"
        tell = change.on?(:signups_notify)
        step(:signups, "Sign-ups moved with the date") do
          signups.instances.each do |instance|
            form = instance.sign_up_form
            SlotManagementService.new(form).regenerate_slots_for_instance!(instance) if form.respond_to?(:slot_generation_mode) && form.slot_generation_mode == "time_based"
          rescue StandardError => e
            Rails.logger.error("[DateChange #{change.id}] slots #{instance.id}: #{e.message}")
          end
          signups.registrations.each do |registration|
            if reopen
              registration.cancel!
              SignUpNotificationService.notify_cancelled(registration) if tell
            elsif tell
              SignUpNotificationService.notify_slot_changed(registration)
            end
          rescue StandardError => e
            Rails.logger.error("[DateChange #{change.id}] sign-up #{registration.id}: #{e.message}")
          end
          n = signups.registrations.size
          if reopen
            "#{n} #{n == 1 ? 'registration' : 'registrations'} canceled and every slot reopened#{tell ? '; those people notified' : ''}"
          else
            "#{n} #{n == 1 ? 'person keeps their' : 'people keep their'} place#{tell ? ', notified of the new time' : ''}"
          end
        end
      end

      def students!
        return unless change.on?(:students_email)

        step(:students, "Students emailed the new time") do
          count = 0
          plan.class_offerings.each do |offering|
            next unless CourseSessionChange.pending?(offering)

            draft = CourseSessionChange.draft(offering)
            CourseSessionChange.start!(offering, subject: change.choice(:students_subject).presence || draft.subject,
                                                 body: change.choice(:students_body).presence || draft.body)
            count += CourseSessionChange.registrations(offering).size
          end
          "#{count} #{count == 1 ? 'student' : 'students'} emailed"
        end
      end
    end
  end
end
