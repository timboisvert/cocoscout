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

  it "delivers the contract_signed_manager template to the chosen managers as a Notification" do
    allow(ContentTemplateService).to receive(:deliver).and_return({ messages: [], emails_queued: 0, channel: :message })

    described_class.perform_now(contract.id)

    expect(ContentTemplateService).to have_received(:deliver).with(
      hash_including(
        template_key: "contract_signed_manager",
        recipients: [ manager_person ],
        organization: org,
        notification: hash_including(category: "contracts", kind: "contract_signed")
      )
    )
  end

  it "lands in the manager's Notifications, linking to the contract, and not in Messages (V1.1 plan §9)" do
    ContentTemplate.find_or_create_by!(key: "contract_signed_manager") do |t|
      t.name = "Contract signed (manager)"
      t.channel = "message"
      t.subject = "{{contractor_name}} signed"
      t.body = "{{contractor_name}} signed the contract for {{production_name}}."
      t.category = "contracts"
    end

    expect { described_class.perform_now(contract.id) }.not_to change(Message, :count)

    notification = manager_user.notifications.last
    expect(notification.title).to eq("Dan Feltey signed")
    expect(notification.path).to eq("/manage/contracts/#{contract.to_param}")
    expect(notification.organization).to eq(org)
    expect(manager_user.unread_notification_count).to eq(1)
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
