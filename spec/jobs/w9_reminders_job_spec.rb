# frozen_string_literal: true

require "rails_helper"

RSpec.describe W9RemindersJob, type: :job do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person, email: "sam@example.com", user: create(:user)) }
  let!(:member) do
    create(:organization_staff_member, organization: org, person: person,
           w9_requested_at: 10.days.ago, w9_last_reminded_at: 8.days.ago)
  end

  it "nudges people asked more than a week ago" do
    expect { described_class.perform_now }.to have_enqueued_mail(StaffTaxFormMailer, :w9_request)
    expect(member.reload.w9_last_reminded_at).to be > 1.minute.ago
    expect(member.w9_requested_at).to be < 9.days.ago
  end

  it "leaves alone people reminded recently, never asked, or already done" do
    member.update!(w9_last_reminded_at: 2.days.ago)
    never_asked = create(:organization_staff_member, organization: org, person: create(:person, user: create(:user)))
    done_person = create(:person, user: create(:user))
    done = create(:organization_staff_member, organization: org, person: done_person,
                  w9_requested_at: 10.days.ago, w9_last_reminded_at: 8.days.ago)
    create(:w9_submission, organization: org, person: done_person, organization_staff_member: done)

    expect { described_class.perform_now }.not_to have_enqueued_mail(StaffTaxFormMailer, :w9_request)
    expect(never_asked.reload.w9_last_reminded_at).to be_nil
  end
end
