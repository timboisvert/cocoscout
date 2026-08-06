# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShiftDeclinedNotificationJob, type: :job do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:manager_user) { create(:user) }
  let!(:manager_person) { create(:person, user: manager_user) }
  let!(:manager_role) { create(:organization_role, :manager, user: manager_user, organization: org) }

  let(:role) { create(:house_role, organization: org, name: "Bartender") }
  let(:shift) { create(:shift, organization: org, house_role: role) }
  let(:worker) { create(:person, name: "Sam Staffer") }
  let(:assignment) { create(:shift_assignment, shift: shift, person: worker) }

  before do
    org.update!(staffing_notification_user_ids: [ manager_user.id ])
    assignment.decline!(reason: "Family thing")
  end

  it "delivers the shift_declined_manager template to the chosen managers as a system message" do
    allow(ContentTemplateService).to receive(:deliver).and_return({ messages: [], emails_queued: 0, channel: :message })

    described_class.perform_now(assignment.id)

    expect(ContentTemplateService).to have_received(:deliver).with(
      hash_including(
        template_key: "shift_declined_manager",
        message_type: :system,
        system_generated: false, # must reach the manage inbox — it's FOR managers
        recipients: [ manager_person ],
        organization: org,
        variables: hash_including(
          person_name: "Sam Staffer",
          role_name: "Bartender",
          decline_reason: "Family thing"
        )
      )
    )
  end

  it "renders the migration-owned template with the reason and a scheduling link" do
    described_class.perform_now(assignment.id)

    message = Message.order(:created_at).last
    expect(message).to be_present
    body = message.body.to_s
    expect(body).to include("Sam Staffer")
    expect(body).to include("Bartender")
    expect(body).to include("Family thing")
    expect(body).to include("View that day in Staffing Scheduling")
    expect(body).to include("week_start=#{shift.starts_at.to_date.beginning_of_week.iso8601}")
    expect(message.message_type).to eq("system")
    expect(message.sender).to be_nil
  end

  it "omits the note line when no reason was given" do
    assignment.update!(decline_reason: nil)

    described_class.perform_now(assignment.id)

    message = Message.order(:created_at).last
    expect(message.body.to_s).not_to include("Their note")
  end

  it "no-ops when the org has selected no recipients" do
    org.update!(staffing_notification_user_ids: [])
    allow(ContentTemplateService).to receive(:deliver)

    described_class.perform_now(assignment.id)

    expect(ContentTemplateService).not_to have_received(:deliver)
  end

  it "no-ops when the decline was undone before the job ran" do
    assignment.undo_decline!
    allow(ContentTemplateService).to receive(:deliver)

    described_class.perform_now(assignment.id)

    expect(ContentTemplateService).not_to have_received(:deliver)
  end

  it "drops a manager who was removed from the chosen list's manager pool" do
    manager_role.destroy!
    allow(ContentTemplateService).to receive(:deliver)

    described_class.perform_now(assignment.id)

    expect(ContentTemplateService).not_to have_received(:deliver)
  end
end
