# frozen_string_literal: true

class ShowChangePlan
  # Delete is for a date entered by mistake (Tim, 2026-11-27): one small
  # confirm, offered only while nobody counts on the date. Once tickets were
  # sold, someone was cast or scheduled, someone signed up, or money was
  # entered for it, the date existed, and it's canceled instead.
  module Delete
    module_function

    PASS_CHANNELS = ShowChangePlan::PASS_CHANNELS

    # What makes the dates real, in plain words; empty when they can go.
    def blockers(shows)
      ids = shows.map(&:id)
      return [] if ids.empty?

      reasons = []
      listing_ids = TicketListing.where(show_id: ids).pluck(:id)
      sold = Ticket.where(ticket_listing_id: listing_ids, status: Ticket::SOLD_STATUSES).count
      if sold.positive?
        buyers = TicketOrder.paid_like.where(ticket_listing_id: listing_ids).distinct.count(Arel.sql("COALESCE(LOWER(buyer_email), id::text)"))
        reasons << "#{sold} #{sold == 1 ? 'ticket' : 'tickets'} sold to #{buyers} #{buyers == 1 ? 'buyer' : 'buyers'}"
      elsif TicketListing.where(id: listing_ids).any?(&:worth_keeping?)
        reasons << "ticket orders that have to be kept"
      end
      cast = ShowPersonRoleAssignment.where(show_id: ids).distinct.count(Arel.sql("assignable_type || assignable_id"))
      staff = ShiftAssignment.active.where(shift_id: Shift.where(source_type: "Show", source_id: ids).select(:id))
                             .or(ShiftAssignment.active.where(shift_id: ShiftShow.where(show_id: ids).select(:shift_id))).distinct.count(:person_id)
      if cast.positive? || staff.positive?
        reasons << [ (cast.positive? ? "#{cast} #{cast == 1 ? 'person' : 'people'} cast" : nil),
                     (staff.positive? ? "#{staff} staff scheduled" : nil) ].compact.join(" and ")
      end
      signups = SignUpRegistration.active.where(sign_up_slot_id: SignUpSlot.where(sign_up_form_instance_id: SignUpFormInstance.where(show_id: ids).select(:id)).select(:id)).count
      reasons << "#{signups} #{signups == 1 ? 'sign-up' : 'sign-ups'}" if signups.positive?
      students = CourseSessionCancellation.summary(shows).registrations.size
      reasons << "#{students} #{students == 1 ? 'student' : 'students'} registered for the class" if students.positive?
      paid = ShowPayout.where(show_id: ids).to_a.select { |p| p.paid? || p.in_payout_run? }
      advances = PersonAdvance.where(show_id: ids).where.not(status: "pending").exists?
      payments = ContractPayment.where(show_id: ids, status: "paid").exists?
      reasons << "pay that went out for it" if paid.any? || advances || payments
      money = [ Bill, Invoice, MoneyRecord ].sum { |model| model.where(show_id: ids).count }
      reasons << "#{money == 1 ? 'a bill, invoice, or money record' : 'bills, invoices, or money records'} entered for it" if money.positive?
      if Show.where(linked_show_id: ids).exists?
        reasons << "another organization's copy of it"
      end
      reasons
    end

    def deletable?(shows) = blockers(shows).empty?

    # Takes the dates off as if they'd never been entered. Anything that
    # only pointed at them (a bank rule, a follower source, an empty shift
    # made for them, a draft follower email) lets go of them first.
    def delete!(shows)
      ids = shows.map(&:id)
      ActiveRecord::Base.transaction do
        [ BankRule, FollowerSource ].each { |model| model.where(show_id: ids).update_all(show_id: nil) }
        ContractPayment.where(show_id: ids, status: %w[pending overdue]).each { |p| p.destroy! unless p.in_payout_run? }
        ContractPayment.where(show_id: ids).update_all(show_id: nil)
        Shift.where(source_type: "Show", source_id: ids).includes(:shift_assignments).each do |shift|
          others = shift.shows.where.not(id: ids).to_a
          if others.any?
            shift.update!(source: others.first)
          elsif shift.shift_assignments.none?
            shift.destroy!
          end
        end
        shows.first.production.organization.follower_emails.drafts.each do |draft|
          left = Array(draft.show_ids).map(&:to_i) - ids
          draft.update!(show_ids: left) if left.size != Array(draft.show_ids).size
        end
        Show.without_contract_payment_sync { shows.each(&:destroy!) }
      end
    end
  end
end
