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
        system_generated: false, # must reach the manage inbox — it's FOR managers
        recipients: [ manager_person ],
        organization: org
      )
    )
  end

  it "lands in the manager's manage inbox (and the badge counts it), attributed as automated" do
    ContentTemplate.find_or_create_by!(key: "contract_signed_manager") do |t|
      t.name = "Contract signed (manager)"
      t.channel = "message"
      t.subject = "{{contractor_name}} signed"
      t.body = "{{contractor_name}} signed the contract for {{production_name}}."
      t.category = "contracts"
    end

    described_class.perform_now(contract.id)

    message = Message.order(:created_at).last
    expect(message.message_type).to eq("system")
    expect(message.system_generated).to be(false)
    expect(message.sender).to be_nil
    expect(message.automated?).to be(true) # never attributed to a user

    inbox = Message.manage_inbox_for(manager_user, org)
    expect(inbox).to include(message)
    # Badge == list invariant.
    expect(manager_user.unread_message_count_for_org(org)).to eq(1)
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
