# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseOfferingCompletionJob, type: :job do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "course") }

  def offering_with_session(status:, session_at:)
    o = create(:course_offering, production: production, status: status)
    create(:show, production: production, course_offering: o, event_type: "class", date_and_time: session_at) if session_at
    o
  end

  it "completes a closed run whose last session has passed" do
    o = offering_with_session(status: "closed", session_at: 2.days.ago)
    described_class.perform_now
    expect(o.reload.status).to eq("completed")
  end

  it "leaves a closed run with an upcoming session alone" do
    o = offering_with_session(status: "closed", session_at: 3.days.from_now)
    described_class.perform_now
    expect(o.reload.status).to eq("closed")
  end

  it "does not complete an open (still accepting) run even if sessions passed" do
    o = offering_with_session(status: "open", session_at: 2.days.ago)
    described_class.perform_now
    expect(o.reload.status).to eq("open")
  end

  it "leaves a closed run with no sessions alone" do
    o = offering_with_session(status: "closed", session_at: nil)
    described_class.perform_now
    expect(o.reload.status).to eq("closed")
  end
end
