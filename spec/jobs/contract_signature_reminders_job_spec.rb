# frozen_string_literal: true

require "rails_helper"

# A signature request used to sit open forever. Now it gets chased on a
# schedule and expires — and the expiry is real, because a deadline you don't
# enforce teaches people to ignore the next one.
RSpec.describe ContractSignatureRemindersJob, type: :job do
  let(:owner) { create(:user) }
  let!(:org) { create(:organization, owner: owner, signature_expiry_days: 14) }
  let!(:manager_person) { create(:person, user: owner) }
  let!(:manager_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:signer) { create(:person, name: "Quinn James", user: create(:user)) }
  let(:contractor) { create(:contractor, organization: org, person: signer) }
  let!(:template) { org.contract_templates.create!(name: "Standard", content: "<p>For {{contractor_name}}</p>") }
  let!(:contract) do
    create(:contract, :active, organization: org, contractor: contractor, contractor_name: "Quinn James",
                               signing_mode: :esign, contract_template: template)
  end

  before do
    org.update!(contract_notification_user_ids: [ owner.id ])
    contract.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
    contract.send_for_signature!
    contract.reload
  end

  def version = contract.reload.current_version

  describe "the nudge schedule" do
    it "sends nothing on the day it goes out" do
      expect { described_class.perform_now }.not_to change { version.nudge_count }
    end

    it "nudges at each scheduled day, once each" do
      version.update!(sent_for_signature_at: 5.days.ago)

      described_class.perform_now
      expect(version.nudge_count).to eq(1)

      # Same day again: no second nudge.
      described_class.perform_now
      expect(version.nudge_count).to eq(1)

      version.update!(sent_for_signature_at: 10.days.ago)
      described_class.perform_now
      expect(version.nudge_count).to eq(2)
    end

    it "gives a 7-day window two nudges and a 14-day window three" do
      version.update!(signature_due_at: version.sent_for_signature_at + 7.days)
      expect(version.nudge_schedule.size).to eq(2)

      version.update!(signature_due_at: version.sent_for_signature_at + 14.days)
      expect(version.reload.nudge_schedule.size).to eq(3)
    end
  end

  describe "expiry" do
    before { version.update!(signature_due_at: 1.day.ago) }

    it "kills the link and hands the contract back ready to send" do
      described_class.perform_now

      contract.reload
      expect(contract.signing_state).to eq("awaiting_send")
      expect(contract.signing_token).to be_nil
      expect(version.expired_at).to be_present
      # The org's signature and the locked document survive.
      expect(version.organization_signature).to be_present
      expect(version.content_snapshot).to be_present
    end

    it "tells both sides" do
      expect { described_class.perform_now }.to change(Message, :count).by_at_least(1)
    end

    it "keeps a staged amendment so re-sending is one click" do
      version.update!(staged_amendment: { "production_name" => "New Name" })

      described_class.perform_now

      expect(version.reload.staged_amendment).to be_present
    end

    it "leaves an already-executed contract alone" do
      version.update!(executed_at: Time.current)
      contract.update!(signing_state: :executed)

      described_class.perform_now

      expect(version.reload.expired_at).to be_nil
    end
  end
end

RSpec.describe ContractAmendmentSummary do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:contract) { create(:contract, :active, organization: org, production_name: "Old Name") }

  it "says what actually changed, in words a person can read" do
    contract.update_draft_step(:payment_config, { "revenue_their_share" => "40" })

    lines = described_class.lines(contract, {
      "payment_config" => { "revenue_their_share" => "50" },
      "production_name" => "New Name"
    })

    expect(lines).to include("Your share goes from 40% to 50%.")
    expect(lines).to include("Renamed to New Name.")
  end

  it "counts dates added" do
    lines = described_class.lines(contract, {
      "new_bookings" => [ { "starts_at" => "2026-11-05T20:00:00" }, { "starts_at" => "2026-11-12T20:00:00" } ]
    })

    expect(lines.first).to eq("2 dates added: Nov 5 and Nov 12.")
  end

  it "stays quiet about things that didn't change" do
    contract.update_draft_step(:payment_config, { "revenue_their_share" => "40" })

    lines = described_class.lines(contract, { "payment_config" => { "revenue_their_share" => "40" } })

    expect(lines).to be_empty
  end
end
