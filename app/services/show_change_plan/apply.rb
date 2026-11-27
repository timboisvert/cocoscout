# frozen_string_literal: true

class ShowChangePlan
  # Does a change once the manager confirms it (DateChangeApplyJob). Each
  # part is a step of its own, marked on the change as it finishes, so the
  # record page shows it happening; anything that couldn't be done is a
  # problem on the change, with what to do about it. Never raises for one
  # buyer's card or one person: those are problems, and the rest goes on.
  class Apply
    def self.call(change, by: change.created_by_user) = new(change, by: by).call

    attr_reader :change, :plan, :by, :organization

    def initialize(change, by:)
      @change = change
      @by = by
      @organization = change.organization
    end

    # The dates themselves couldn't change, so nothing else is done.
    class Stopped < StandardError; end

    def call
      change.update!(batch: change.batch.presence || SecureRandom.uuid)
      @plan = ShowChangePlan.new(change)
      begin
        Current.set(show_change_batch: change.batch, show_change_off_ids: (change.cancel? ? plan.acting_ids : nil)) do
          case change.kind
          when "cancel" then Cancel.new(self).run
          when "restore" then Restore.new(self).run
          when "move" then MoveRun.new(self).run
          end
        end
      rescue Stopped
        skip_the_rest!("Not done: the dates didn't change.")
      rescue StandardError => e
        # Never left spinning: whatever was running is a problem, the rest
        # is marked not done, and the page says so.
        Rails.logger.error("[DateChange #{change.id}] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
        Sentry.capture_exception(e) if defined?(Sentry)
        change.add_problem!(key: "stopped", kind: "step", label: "CocoScout stopped partway through.", detail: e.message)
        skip_the_rest!("Not done: CocoScout stopped before this step.")
      end
      # The change is the record now: its cast and staff notices were sent
      # from here (or left out on purpose), so Home doesn't list them again.
      ShowChange.where(organization: organization, batch: change.batch)
                .update_all(closed_at: Time.current, changed_by_user_id: by&.id)
      change.update!(status: "applied") unless change.status == "applied"
      change
    end

    def skip_the_rest!(words)
      change.reload.steps.each do |entry|
        next if entry["status"].in?(%w[done problem skipped])

        if entry["status"] == "running"
          change.mark_step!(entry["key"], status: "problem", detail: "This step stopped partway.")
        else
          change.mark_step!(entry["key"], status: "skipped", detail: "#{entry['label']}. #{words}")
        end
      end
    end

    # Runs one step: marks it running, yields, marks it done with whatever
    # the block returns as its detail. A failure is the step's problem, and
    # the steps after it still run; critical: true (the dates themselves)
    # stops everything after it instead.
    def step(key, label, critical: false)
      change.mark_step!(key, label: label, status: "running")
      detail = yield
      change.mark_step!(key, status: "done", detail: detail.is_a?(String) ? detail : nil)
    rescue StandardError => e
      Rails.logger.error("[DateChange #{change.id}] #{key}: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      Sentry.capture_exception(e) if defined?(Sentry) && !e.is_a?(ActiveRecord::RecordInvalid)
      reason = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
      if critical
        change.mark_step!(key, status: "problem", detail: "#{label.sub(/\A\w/, &:upcase)}: this couldn't be done, so nothing else was. #{reason}")
        change.add_problem!(key: "step-#{key}", kind: "step", label: "The dates couldn't change, so nothing else was done.", detail: reason)
        raise Stopped
      end
      change.mark_step!(key, status: "problem", detail: "This step stopped partway: #{reason}")
      change.add_problem!(key: "step-#{key}", kind: "step", label: "#{label} stopped partway.", detail: reason)
    end

    def remember!(key, value)
      change.with_lock do
        change.update_columns(undo: change.undo.merge(key.to_s => value))
      end
    end

    def words(key, kind)
      draft = BuyerWords.draft(kind)
      [ change.choice("#{key}_subject").presence || draft[:subject], change.choice("#{key}_body").presence || draft[:body] ]
    end

    def notices = ShowChangeNotices.for_batch(organization, change.batch)

    # The edited cast or staff words, or the template's when untouched.
    def notice_words(notices, section, prefix)
      draft = notices.draft(section)
      [ change.choice("#{prefix}_subject").presence || draft[:subject], change.choice("#{prefix}_body").presence || draft[:body] ]
    end

    def deliver_person(template_key, person, variables, show: nil, production: nil)
      ContentTemplateService.deliver(
        template_key: template_key, variables: variables, sender: nil, recipients: [ person ],
        organization: organization, production: production || show&.production, show: show,
        message_type: :system, visibility: :personal,
        mailer_class: ShowChangeMailer.with(organization_id: organization.id), mailer_method: :notice
      )
    end

    # A cast member who can't do a date: their roles on it open for cover,
    # the way the casting page's Open for cover does it.
    def open_roles_for_cover!(show, person)
      assignments = show.show_person_role_assignments.includes(:role).where(assignable_type: "Person", assignable_id: person.id).to_a
      assignments.map do |assignment|
        RoleVacancy.create!(show: show, role: assignment.role, vacated_by: person, vacated_at: Time.current, status: :open)
        role = assignment.role&.name
        assignment.destroy!
        role
      end.tap { show.reopen_casting! if assignments.any? && show.respond_to?(:casting_finalized?) && show.casting_finalized? }
    end

    def first_name(person) = person.name.to_s.split(/\s+/).first.presence || person.name.to_s
    def day(time) = time.strftime("%a, %b %-d")
    def day_time(time) = "#{time.strftime('%a, %b %-d')}, #{time.strftime('%-l:%M %p').strip}"

    # ---- Cancel -----------------------------------------------------------

    class Cancel
      delegate :change, :plan, :by, :organization, :step, :remember!, :words, :notices, :notice_words,
               :deliver_person, :first_name, :day, :day_time, :open_roles_for_cover!, to: :@apply

      def initialize(apply)
        @apply = apply
      end

      def run
        shows = plan.acting_shows
        buyers = plan.buyers
        cast = plan.cast
        staff = plan.staff
        signups = plan.signups
        students = plan.students
        money = plan.money
        drafts = plan.follower_drafts
        releasing = plan.rentals_to_release
        undo_shifts = staff.changing_shifts.map do |shift|
          { "shift_id" => shift.id, "coverage_mode" => shift.coverage_mode,
            "person_ids" => shift.active_assignments.filter_map(&:person_id) }
        end

        step(:dates, "#{shows.size == 1 ? 'The date' : "#{shows.size} dates"} canceled, ticket sales stopped", critical: true) do
          # All of the dates or none: a date that can't be canceled (one that
          # follows another organization's contract, say) leaves every date
          # as it was, and nobody is refunded or notified.
          ActiveRecord::Base.transaction { cancel_dates!(shows, releasing, money.contract_payments) }
          "#{shows.size == 1 ? '1 date' : "#{shows.size} dates"} canceled#{plan.listings.any? ? ', ticket sales stopped' : ''}"
        end

        buyers!(buyers) if buyers.any?
        cast!(cast) if cast.any?
        staff!(staff, undo_shifts) if staff.any?
        signups!(signups) if signups.registrations.any?
        students!(shows, students) if students.any?
        money!(money, drafts) if money.payouts.any? || money.expenses.any? || drafts.any?
      end

      def cancel_dates!(shows, releasing, contract_payments)
        statuses = plan.listings.to_h { |l| [ l.id.to_s, l.status ] }
        remember!(:listing_statuses, statuses)
        remember!(:table_events, plan.cast.table_events.map { |e| { "casting_table_id" => e.casting_table_id, "show_id" => e.show_id } })
        remember!(:rentals, releasing.map { |r| r.attributes.except("id", "created_at", "updated_at").merge("show_ids" => Show.where(space_rental_id: r.id).pluck(:id)) })

        shows.each do |show|
          show.duration_minutes ||= show.space_rental&.effective_duration_minutes if show.space_rental_id
          show.canceled = true
          show.save!
        end
        plan.listings.each { |listing| listing.update!(status: "canceled") unless listing.status == "canceled" }

        # Pending money for the dates comes off; anything paid or on a payout
        # run already moved, and stays with the canceled date.
        contract_payments.each { |payment| payment.destroy! unless payment.in_payout_run? }

        # The room is free again: a canceled date that kept its booking would
        # hold the space against everyone else.
        contracts = releasing.map(&:contract).uniq
        releasing.each(&:destroy!)
        contracts.each { |c| c.refresh_dates_from_rentals! if c.respond_to?(:refresh_dates_from_rentals!) }

        plan.cast.table_events.each(&:destroy!)
      end

      # One pass over the buyers, each buyer's orders together, so each gets
      # one email about all of their tickets.
      def buyers!(buyers)
        rebook = change.choice(:buyers_action) == "rebook" ? TicketListing.find_by(id: change.choice(:rebook_listing_id)) : nil
        mark_other = change.on?(:other_paid)
        email_comps = change.on?(:comps_email)
        subject, body = words(:buyers, :cancel)
        card = buyers.card
        refunded_ids = []
        counts = Hash.new(0)
        card_cents = 0

        main_key = rebook ? :rebook : :refunds
        main_label = rebook ? "Moving #{buyers.buyer_count == 1 ? "1 buyer's" : "#{buyers.buyer_count} buyers'"} tickets to #{day(rebook.show.date_and_time)}" : "Refunding #{buyers.buyer_count(card)} #{buyers.buyer_count(card) == 1 ? 'buyer' : 'buyers'}"
        change.mark_step!(main_key, label: main_label, status: "running", total: (rebook ? buyers.orders.size : card.size), done_count: 0, cents: 0) if card.any? || rebook
        if buyers.other.any? || buyers.pass.any?
          change.mark_step!(:other_paid, label: other_label(buyers, mark_other), status: "running")
        end
        change.mark_step!(:comps, label: comps_label(buyers, email_comps), status: "running") if buyers.comps.any? || buyers.comp_requests.any?

        buyers.orders.group_by { |o| o.email || "order-#{o.order.id}" }.each_value do |rows|
          results = []
          rows.each do |row|
            order = row.order
            begin
              if rebook && row.kind != :pass
                exchange = TicketOrderExchange.exchange!(order, target: rebook, by: by, email_them: false, outside_policy: true)
                counts[:rebooked] += 1
                if order.buyer_email.present?
                  variables = BuyerWords.rebooked_variables(order, exchange.to_order)
                  rb_subject, rb_body = words(:rebook, :rebook)
                  TicketOrderMailer.date_change(exchange.to_order, subject: rb_subject, body: rb_body, variables: variables).deliver_later
                end
                tick!(:rebook)
                next
              end

              case row.kind
              when :card
                refund = TicketOrderRefund.issue!(order, by: by, reason: "Date canceled", notify: false, outside_policy: true, reprice: false)
                if refund.respond_to?(:status) && refund.status == "failed"
                  raise TicketOrderRefund::Error, refund.error.to_s
                end
                results << [ order, :refunded, refund ]
                refunded_ids << order.id
                card_cents += refund.amount_cents
                tick!(:refunds, cents: card_cents)
              when :other
                next unless mark_other

                refund = TicketOrderRefund.issue!(order, by: by, reason: "Date canceled (paid another way)", notify: false, outside_policy: true, reprice: false)
                results << [ order, :marked, refund ]
                refunded_ids << order.id
                counts[:marked] += 1
              when :pass
                TicketPassCredits.return!(order, by: by)
                results << [ order, :credit ]
                counts[:credits] += 1
              when :comp
                TicketOrderRefund.issue!(order, by: by, reason: "Date canceled", notify: false, outside_policy: true, reprice: false)
                results << [ order, :comp ] if email_comps
                counts[:comps] += 1
              end
            rescue StandardError => e
              refund_problem!(row, e)
              tick!(:refunds, cents: card_cents, failed: true) if row.kind == :card
            end
          end
          send_canceled_email(results, subject, body) if results.any?
        end
        remember!(:refunded_order_ids, refunded_ids)

        buyers.comp_requests.each do |request|
          request.close!("canceled")
          counts[:requests] += 1
        rescue StandardError => e
          Rails.logger.error("[DateChange #{change.id}] comp request #{request.id}: #{e.message}")
        end

        if card.any? || rebook
          failed = change.open_problems.count { |p| p["kind"] == "refund" }
          detail = if rebook then "#{counts[:rebooked]} #{counts[:rebooked] == 1 ? 'order' : 'orders'} moved to #{day(rebook.show.date_and_time)}, and the buyers emailed"
          else
            done = refunded_ids.size - counts[:marked]
            went = done.zero? ? nil : "#{done} #{done == 1 ? 'order' : 'orders'} refunded #{BuyerWords.money(card_cents)}, and #{done == 1 ? 'the buyer' : 'the buyers'} emailed"
            [ went, (failed.positive? ? "#{failed} #{failed == 1 ? "refund didn't" : "refunds didn't"} go through" : nil) ].compact.join("; ").upcase_first
          end
          change.mark_step!(main_key, status: (failed.positive? ? "problem" : "done"), detail: detail)
        end
        if buyers.other.any? || buyers.pass.any?
          parts = []
          parts << "#{counts[:marked]} #{counts[:marked] == 1 ? 'order' : 'orders'} paid another way marked refunded" if counts[:marked].positive?
          parts << "#{counts[:credits]} pass #{counts[:credits] == 1 ? "holder's credits" : "holders' credits"} returned" if counts[:credits].positive?
          parts << "Orders paid another way left as they are" if parts.empty?
          change.mark_step!(:other_paid, status: "done", detail: parts.join("; "))
        end
        if buyers.comps.any? || buyers.comp_requests.any?
          parts = []
          parts << "#{counts[:comps]} comp #{counts[:comps] == 1 ? 'order' : 'orders'} canceled#{email_comps ? ' and emailed' : ''}" if counts[:comps].positive?
          parts << "#{counts[:requests]} comp #{counts[:requests] == 1 ? 'request' : 'requests'} closed, and #{counts[:requests] == 1 ? 'the person' : 'each person'} who requested notified" if counts[:requests].positive?
          change.mark_step!(:comps, status: "done", detail: parts.join("; "))
        end
      end

      def other_label(buyers, mark)
        parts = []
        parts << "#{buyers.other.size} #{buyers.other.size == 1 ? 'order' : 'orders'} paid another way #{mark ? 'marked refunded' : 'left as they are'}" if buyers.other.any?
        parts << "#{buyers.buyer_count(buyers.pass)} pass holders' credits returned" if buyers.pass.any?
        parts.join("; ")
      end

      def comps_label(buyers, email)
        parts = []
        parts << "Comp holders #{email ? 'emailed' : 'not emailed'}" if buyers.comps.any?
        parts << "#{buyers.comp_requests.size} comp #{buyers.comp_requests.size == 1 ? 'request' : 'requests'} closed" if buyers.comp_requests.any?
        parts.join("; ")
      end

      def tick!(key, cents: nil, failed: false)
        change.with_lock do
          list = change.steps.map(&:dup)
          entry = list.find { |s| s["key"] == key.to_s }
          next unless entry

          entry["done_count"] = entry["done_count"].to_i + 1 unless failed
          entry["failed_count"] = entry["failed_count"].to_i + 1 if failed
          entry["cents"] = cents if cents
          change.update_columns(steps: list, updated_at: Time.current)
        end
      end

      def refund_problem!(row, error)
        order = row.order
        name = order.buyer_name.presence || order.buyer_email.presence || "Order #{order.code}"
        label = case row.kind
        when :card then (change.choice(:buyers_action) == "rebook" ? "#{name}'s tickets couldn't move to the other date, and weren't refunded." : "#{name}'s refund didn't go through.")
        when :pass then "#{name}'s pass credit couldn't be returned."
        else "#{name}'s order couldn't be canceled."
        end
        # Try again refunds the order (a pass's credit can't be refunded on its own).
        change.add_problem!(key: "order-#{order.id}", kind: (row.kind == :pass ? "order" : "refund"), label: label,
                            detail: error.message, order_id: order.id)
      end

      def send_canceled_email(results, subject, body)
        order = results.first.first
        return if order.buyer_email.blank?

        variables = BuyerWords.canceled_variables(results)
        TicketOrderMailer.date_change(order, subject: subject, body: body, variables: variables).deliver_later
      end

      def cast!(cast)
        n = cast.people.size
        step(:cast, "Cast notified#{cast.vacancies.any? ? "; #{cast.vacancies.size} \"can't make it\" #{cast.vacancies.size == 1 ? 'request' : 'requests'} closed" : ''}") do
          told = 0
          list = notices
          section = list.section("cast_off")
          if section && change.on?(:cast_notify)
            subject, body = notice_words(list, section, :cast)
            told = list.send!("cast_off", person_ids: section.reachable.map { |r| r.person.id }, subject: subject, body: body, sender: by)
          end
          cast.unreachable.each do |c|
            next unless change.on?(:cast_notify)

            change.add_problem!(key: "person-#{c.person.id}", kind: "untold", person_id: c.person.id,
                                label: "#{c.person.name} (cast) doesn't have a CocoScout login or an email, so #{c.person.name} needs to hear it from you directly.")
          end
          covers = 0
          cast.vacancies.each do |vacancy|
            vacancy.cancel!(by: by)
            vacancy.invitations.each do |invitation|
              next unless invitation.person

              deliver_person("date_change_cover_not_needed", invitation.person, {
                recipient_name: first_name(invitation.person), organization_name: organization.name,
                production_name: vacancy.show.production.name, role_name: vacancy.role&.name.to_s,
                show_label: "#{vacancy.show.production.name}, #{day_time(vacancy.show.date_and_time)}"
              }, show: vacancy.show)
              covers += 1
            end
          end
          parts = [ change.on?(:cast_notify) ? "#{told} of #{n} cast notified" : "The cast weren't notified" ]
          parts << "#{cast.vacancies.size} \"can't make it\" #{cast.vacancies.size == 1 ? 'request' : 'requests'} closed#{covers.positive? ? ", and #{covers} #{covers == 1 ? 'person' : 'people'} invited to cover notified" : ''}" if cast.vacancies.any?
          parts << "the dates came off #{cast.table_events.map { |e| e.casting_table.name }.uniq.to_sentence}" if cast.table_events.any?
          parts.join("; ")
        end
      end

      def staff!(staff, undo_shifts)
        remember!(:shifts, undo_shifts)
        off = change.on?(:shifts_off)
        tell = change.on?(:staff_notify)
        step(:staff, "#{staff.changing_shifts.size} #{staff.changing_shifts.size == 1 ? 'shift' : 'shifts'} off the schedule; staff notified") do
          list = notices
          section = list.section("staff_off")
          told = 0
          if section
            if tell
              subject, body = notice_words(list, section, :staff)
              told = list.send!("staff_off", person_ids: section.reachable.map { |r| r.person.id }, subject: subject, body: body,
                                             sender: by, shift_action: off)
            elsif off
              list.take_shifts_off!(section)
            end
          end
          if off
            staff.changing_shifts.each do |shift|
              shift.reload
              shift.update!(coverage_mode: :not_needed) unless shift.not_needed?
            end
            staff.vacancies.each { |v| v.cancel!(by: by) }
          end
          parts = []
          parts << (off ? "#{staff.changing_shifts.size} #{staff.changing_shifts.size == 1 ? 'shift' : 'shifts'} off the schedule" : "The shifts stay on the schedule")
          parts << (tell ? "#{told} #{told == 1 ? 'person' : 'people'} on staff notified" : "the staff weren't notified") if staff.people.any?
          parts << "#{staff.vacancies.size} cover #{staff.vacancies.size == 1 ? 'request' : 'requests'} closed" if off && staff.vacancies.any?
          parts << "#{staff.staying.map { |l| l.person&.name }.compact.uniq.to_sentence} #{staff.staying.map(&:person).compact.uniq.one? ? 'stays' : 'stay'} on" if staff.staying.any? { |l| l.person }
          parts.join("; ")
        end
      end

      def signups!(signups)
        cancel = change.on?(:signups_cancel)
        step(:signups, "Sign-ups canceled and notified; sign-up closed for these dates") do
          if cancel
            signups.registrations.each do |registration|
              registration.cancel!
              SignUpNotificationService.notify_cancelled(registration)
            rescue StandardError => e
              Rails.logger.error("[DateChange #{change.id}] sign-up #{registration.id}: #{e.message}")
            end
            "#{signups.registrations.size} #{signups.registrations.size == 1 ? 'sign-up' : 'sign-ups'} canceled and notified; the sign-up closed for these dates"
          else
            "The sign-up closed for these dates; the #{signups.registrations.size} registrations were left as they are"
          end
        end
      end

      def students!(shows, students)
        step(:students, "Students emailed") do
          if change.on?(:students_email)
            draft = CourseSessionCancellation.default_email
            subject = change.choice(:students_subject).presence || draft.first
            body = change.choice(:students_body).presence || draft.last
            count = CourseSessionCancellation.start!(shows, subject: subject, body: body)
            "#{count} #{count == 1 ? 'student' : 'students'} emailed"
          else
            "The students weren't emailed"
          end
        end
      end

      def money!(money, drafts)
        step(:money, "Money and follower emails updated") do
          parts = []
          if money.payouts.any? && change.on?(:clear_pay)
            money.payouts.each { |payout| payout.destroy! unless payout.reload.paid? || payout.in_payout_run? }
            parts << "unpaid pay for #{money.payouts.size == 1 ? 'the date' : "#{money.payouts.size} dates"} cleared"
          end
          if money.expenses.any? && change.on?(:respread)
            money.expenses.each(&:recalculate_allocations!)
            parts << "#{money.expenses.map(&:name).to_sentence} spread over the dates still on"
          end
          if drafts.any? && change.on?(:followers)
            ids = plan.acting_ids
            drafts.each { |draft| draft.update!(show_ids: Array(draft.show_ids).map(&:to_i) - ids) }
            parts << "the dates taken out of #{drafts.size == 1 ? 'the follower email draft' : "#{drafts.size} follower email drafts"}"
          end
          parts.empty? ? "Nothing changed" : parts.join("; ").upcase_first
        end
      end
    end
  end
end
