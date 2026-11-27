# frozen_string_literal: true

class ShowChangePlan
  class Apply
    # Bringing canceled dates back (Tim, 2026-11-27): the dates and their
    # ticket sales come back as they were, the cast stayed in their roles,
    # the staff go back on the shifts the cancel took them off, unless
    # something since says they can't. Refunds and sent messages stand.
    class Restore
      delegate :change, :plan, :by, :organization, :step, :remember!, :words, :deliver_person, :first_name,
               :day, :day_time, :open_roles_for_cover!, to: :@apply

      def initialize(apply)
        @apply = apply
      end

      def cancel = change.restores
      def undo = cancel&.undo || {}

      def run
        shows = plan.acting_shows
        ids = shows.map(&:id)

        step(:dates, "#{shows.size == 1 ? 'The date is' : "#{shows.size} dates are"} back on") do
          bring_back!(shows, ids)
        end
        buyers!(ids) if change.on?(:buyers_email, default: false)
        cast!(shows) if change.on?(:cast_notify)
        staff!(ids) if change.on?(:staff_back)
      end

      def bring_back!(shows, ids)
        shows.each do |show|
          show.canceled = false
          show.save!
        rescue ActiveRecord::RecordInvalid => e
          change.add_problem!(key: "restore-#{show.id}", kind: "show", label: "#{show.production.name}, #{day_time(show.date_and_time)} couldn't come back.",
                              detail: e.record.errors.full_messages.to_sentence)
        end
        statuses = undo["listing_statuses"] || {}
        TicketListing.where(show_id: ids, status: "canceled").find_each do |listing|
          was = statuses[listing.id.to_s].presence
          was = "on_sale" if was.nil? || was == "canceled"
          listing.update_columns(status: was, updated_at: Time.current)
        end
        Array(undo["table_events"]).each do |row|
          next unless ids.include?(row["show_id"].to_i)

          CastingTableEvent.find_or_create_by!(casting_table_id: row["casting_table_id"], show_id: row["show_id"])
        rescue StandardError => e
          Rails.logger.error("[DateChange #{change.id}] table event: #{e.message}")
        end
        rooms = rebook_rooms!(ids)
        [ "#{shows.size == 1 ? 'The date is' : "#{shows.size} dates are"} back on",
          (plan.listings.any? ? "ticket sales reopened" : nil), rooms ].compact.join("; ")
      end

      # The room the cancel let go, booked again if it's still free.
      def rebook_rooms!(ids)
        booked = 0
        Array(undo["rentals"]).each do |attrs|
          show_ids = Array(attrs["show_ids"]).map(&:to_i) & ids
          next if show_ids.empty?

          rental = SpaceRental.new(attrs.except("show_ids"))
          if rental.save
            Show.where(id: show_ids).update_all(space_rental_id: rental.id)
            rental.contract.refresh_dates_from_rentals! if rental.contract.respond_to?(:refresh_dates_from_rentals!)
            booked += 1
          else
            change.add_problem!(key: "rental-#{show_ids.first}", kind: "room", label: "The room couldn't be booked again for #{day(rental.starts_at)}.",
                                detail: rental.errors.full_messages.to_sentence)
          end
        end
        booked.positive? ? "the room booked again" : nil
      end

      def buyers!(ids)
        orders = plan.refunded_orders.select { |o| ids.include?(o.ticket_listing.show_id) && o.buyer_email.present? }
        return if orders.empty?

        step(:buyers, "Refunded buyers emailed that it's back on") do
          subject, body = words(:back_on, :back_on)
          groups = orders.group_by { |o| o.buyer_email.to_s.strip.downcase }
          groups.each_value do |list|
            TicketOrderMailer.date_change(list.first, subject: subject, body: body, variables: BuyerWords.back_on_variables(list)).deliver_later
          end
          "#{groups.size} refunded #{groups.size == 1 ? 'buyer' : 'buyers'} emailed that it's back on"
        end
      end

      def cast!(shows)
        people = plan.cast.people
        return if people.empty?

        step(:cast, "Cast notified that it's back on") do
          told = 0
          opened = 0
          people.each do |entry|
            person = entry.person
            mine = shows.select { |s| entry.dates.include?(s.date_and_time) }
            cover = nil
            mine.each do |show|
              next unless ShowAvailability.where(show: show, available_entity: person, status: :unavailable).exists?

              roles = open_roles_for_cover!(show, person)
              next if roles.empty?

              opened += 1
              cover = "You marked #{day(show.date_and_time)} as unavailable, so #{roles.compact.to_sentence} that night is open for cover."
            end
            next unless entry.reachable?

            deliver_person("show_back_on", person, {
              recipient_name: first_name(person), organization_name: organization.name,
              production_name: mine.first&.production&.name || plan.origin.production.name,
              dates: mine.map { |s| day_time(s.date_and_time) }.to_sentence, roles: entry.roles.to_sentence, cover: cover.to_s
            }, show: (mine.first if mine.one?), production: mine.first&.production)
            told += 1
          end
          "#{told} cast notified#{opened.positive? ? "; #{opened} #{opened == 1 ? 'role' : 'roles'} opened for cover" : ''}"
        end
      end

      # The people the cancel took off, back on the same shifts, unless
      # they've taken another shift that overlaps since.
      def staff!(ids)
        rows = Array(undo["shifts"])
        return if rows.empty?

        step(:staff, "Staff back on their shifts and notified") do
          back = Hash.new { |h, k| h[k] = [] }
          opened = 0
          rows.each do |row|
            shift = organization.shifts.find_by(id: row["shift_id"])
            next unless shift
            next unless (shift.covered_shows.map(&:id) & ids).any? || shift.source.nil?

            shift.update!(coverage_mode: row["coverage_mode"].presence || "needs_assignment") if shift.not_needed?
            Array(row["person_ids"]).each do |person_id|
              next if shift.shift_assignments.active.where(person_id: person_id).exists?

              clash = ShiftAssignment.active.joins(:shift).where(person_id: person_id).where.not(shift_id: shift.id)
                                     .where("shifts.starts_at < ? AND shifts.ends_at > ?", shift.ends_at, shift.starts_at).exists?
              if clash
                opened += 1
                next
              end
              shift.shift_assignments.create!(person_id: person_id)
              back[person_id] << shift
            end
          end
          people = Person.where(id: back.keys).includes(:user).index_by(&:id)
          back.each do |person_id, shifts|
            person = people[person_id]
            next unless person && (person.user || person.email.present?)

            sorted = shifts.sort_by(&:starts_at)
            deliver_person("shift_back_on", person, {
              recipient_name: first_name(person), organization_name: organization.name, production_name: "",
              headline: "#{sorted.first.role_label}, #{day_time(sorted.first.starts_at)}",
              shifts: sorted.map { |s| "#{s.role_label}, #{day_time(s.starts_at)}" }.join("<br>")
            })
          end
          "#{back.size} on staff back on #{back.values.sum(&:size)} #{back.values.sum(&:size) == 1 ? 'shift' : 'shifts'} and notified" \
            "#{opened.positive? ? "; #{opened} #{opened == 1 ? 'shift opens' : 'shifts open'} for cover, since #{opened == 1 ? 'that person' : 'those people'} took another shift that overlaps" : ''}"
        end
      end
    end
  end
end
