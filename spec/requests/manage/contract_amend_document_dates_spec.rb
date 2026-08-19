# frozen_string_literal: true

require "rails_helper"

# The document a counterparty is asked to sign after an amendment must
# describe the schedule as amended. Amendments edit the contract's space
# rentals and payments — never the creation wizard's draft bookings — so a
# document built from the draft would send the original dates back out.
RSpec.describe "Amended contract documents carry the amended dates", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:template) do
    org.contract_templates.create!(name: "Residency", content: "<p>Deal for {{production_name}}</p>{{license_schedule}}")
  end
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Random Memory") }
  let(:original_at) { Time.zone.local(2026, 10, 2, 20, 0) }
  let(:moved_at) { Time.zone.local(2026, 10, 9, 20, 0) }
  let(:added_at) { Time.zone.local(2026, 11, 6, 20, 0) }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template,
                               contract_start_date: original_at.to_date, contract_end_date: original_at.to_date,
                               draft_data: { "bookings" => [ { "location_id" => location.id, "starts_at" => original_at.iso8601, "duration" => "2" } ] })
  end
  let!(:rental) do
    contract.space_rentals.create!(location: location, starts_at: original_at, ends_at: original_at + 2.hours, confirmed: true)
  end
  let!(:show) { production.shows.create!(date_and_time: original_at, duration_minutes: 120, location: location, space_rental: rental) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.execute_by_signature!(signer_name: "Quinn", signer_email: "q@example.com",
                                   request: double(remote_ip: "1.2.3.4", user_agent: "rspec"))
    contract.reload
  end

  it "starts from a document that names the booked date" do
    expect(contract.current_version.content_snapshot).to include("Fri Oct 2, 2026")
  end

  describe "changing the deal (re-signature)" do
    it "puts the added date on the document and drops the removed one, without touching the live contract" do
      contract.update_amend_data(
        "removed_rental_ids" => [ rental.id ],
        "new_bookings" => [ { "location_id" => location.id, "starts_at" => added_at.iso8601, "duration" => "2" } ]
      )

      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      document = contract.reload.current_version.content_snapshot
      expect(document).to include("Fri Nov 6, 2026")
      expect(document).not_to include("Fri Oct 2, 2026")
      # The proposal isn't in force yet: the live schedule is unchanged.
      expect(contract.space_rentals.pluck(:starts_at)).to eq([ original_at ])
    end

    it "shortens the term when the last night is dropped, and states it in the deal terms" do
      plain = org.contract_templates.create!(name: "Plain", content: "<p>Deal for {{production_name}}</p>")
      contract.update!(contract_template: plain)
      later = contract.space_rentals.create!(location: location, starts_at: added_at, ends_at: added_at + 2.hours, confirmed: true)
      contract.update!(contract_end_date: added_at.to_date)

      contract.update_amend_data("removed_rental_ids" => [ later.id ])
      post apply_amendments_manage_contract_path(contract), params: { requires_signature: "1" }

      document = contract.reload.current_version.content_snapshot
      expect(document).to include("<strong>Term:</strong> October 2, 2026 – October 2, 2026")
    end
  end

  describe "changing the dates, then re-signing" do
    it "renders the moved date, not the one the wizard wrote down" do
      post apply_amend_dates_manage_contract_path(contract),
           params: { dates: { rental.id.to_s => { action: "move", starts_at: moved_at.iso8601 } } }
      contract.reload

      html = contract.render_signable_document.to_s
      expect(html).to include("Fri Oct 9, 2026")
      expect(html).not_to include("Fri Oct 2, 2026")
    end
  end
end
