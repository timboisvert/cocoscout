# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractSignedNotificationJob, type: :job do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:manager_user) { create(:user) }
  let!(:manager_person) { create(:person, user: manager_user) }
  let!(:manager_role) { create(:organization_role, :manager, user: manager_user, organization: org) }
  let(:contract) do
    create(:contract, organization: org, contractor_name: "Dan Feltey", production_name: "The Loop",
      signing_mode: :esign, signing_state: :executed, executed_at: Time.current)
  end

  before { org.update!(contract_notification_user_ids: [ manager_user.id ]) }

  it "delivers the contract_signed_manager template to the chosen managers as a system message" do
    allow(ContentTemplateService).to receive(:deliver).and_return({ messages: [], emails_queued: 0, channel: :message })

    described_class.perform_now(contract.id)

    expect(ContentTemplateService).to have_received(:deliver).with(
      hash_including(
        template_key: "contract_signed_manager",
        message_type: :system,
        recipients: [ manager_person ],
        organization: org
      )
    )
  end

  it "no-ops when the org has selected no recipients" do
    org.update!(contract_notification_user_ids: [])
    allow(ContentTemplateService).to receive(:deliver)

    described_class.perform_now(contract.id)

    expect(ContentTemplateService).not_to have_received(:deliver)
  end

  it "no-ops when the contract isn't executed yet" do
    contract.update!(signing_state: :out_for_signature)
    allow(ContentTemplateService).to receive(:deliver)

    described_class.perform_now(contract.id)

    expect(ContentTemplateService).not_to have_received(:deliver)
  end
end
