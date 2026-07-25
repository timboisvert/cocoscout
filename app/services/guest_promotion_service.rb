# frozen_string_literal: true

# Promotes a guest performer (a bare name on a show payout) into a real Person,
# so they can connect a bank and be paid through a payout run like everyone else.
#
# Guest identity lives on the cast assignment (assignable_id: nil + guest_name),
# and the payout line item is derived from it — so we convert both: the
# assignment becomes the Person (source of truth, survives recalculation) and the
# line item is updated in place (preserving its amount) and made ledger-eligible.
class GuestPromotionService
  Result = Struct.new(:person, :error, keyword_init: true)

  def self.promote!(line_item:, email:)
    return Result.new(error: "That line isn't a guest.") unless line_item.is_guest?

    email = email.to_s.strip.downcase
    return Result.new(error: "Enter a valid email so we can pay them.") if email.blank?

    org = line_item.show_payout.production.organization
    show = line_item.show_payout.show
    guest_name = line_item.guest_name

    person = nil
    ActiveRecord::Base.transaction do
      person = org.people.where("LOWER(email) = ?", email).first ||
               org.people.create!(name: guest_name.presence || email.split("@").first, email: email)

      # Convert the guest cast assignment(s) to this Person (the durable identity).
      show.show_person_role_assignments
          .where(assignable_id: nil, guest_name: guest_name)
          .update_all(assignable_type: "Person", assignable_id: person.id, guest_name: nil, updated_at: Time.current)

      # Convert the payout line item in place, preserving its amount, and post the
      # earning to the ledger now that it's a real (ledger-eligible) payee.
      line_item.update!(payee: person, is_guest: false, guest_name: nil)
      line_item.sync_earning_ledger_entry!
    end

    Result.new(person: person)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(error: e.message)
  end
end
