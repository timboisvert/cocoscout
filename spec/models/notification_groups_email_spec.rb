# frozen_string_literal: true

require "rails_helper"

# Fewer emails (Tim, 2026-11-09): a notice that is a notification emails
# someone with an account only when it is time-critical and their Email
# switch for its group is on. Someone with no account still gets the email:
# it is all they have.
RSpec.describe NotificationGroups, ".email?" do
  let(:member) { create(:person, user: create(:user)) }
  let(:no_account) { create(:person) }

  it "leaves alone a template that isn't a notification" do
    expect(described_class.email?("ticket_order_confirmation", member)).to be(true)
    expect(described_class.email?("invoice", member)).to be(true)
  end

  it "emails someone with no account whatever the notice" do
    %w[staff_schedule_notification shift_vacancy_filled shift_canceled vacancy_created].each do |key|
      expect(described_class.email?(key, no_account)).to be(true), key
    end
  end

  it "sends someone with an account the notification only, unless it's time-critical" do
    # What managers and a production team hear about cover, and hours approved.
    quiet = %w[shift_declined_manager shift_vacancy_filled shift_vacancy_reclaimed vacancy_created vacancy_filled vacancy_reclaimed staff_hours_approved]
    quiet.each { |key| expect(described_class.email?(key, member)).to be(false), key }
    # Everything about a person's own shifts still emails (Tim, 2026-11-09: "those should all be emails").
    shifts = %w[staff_schedule_notification staff_schedule_changes staff_shift_added staff_shift_changed staff_shift_removed
                shift_canceled shift_moved shift_claim_confirmed]
    expect(shifts - described_class::EMAILS_TOO).to be_empty
    # Except the day-before reminder: a notification only (Tim, 2026-11-10).
    expect(described_class.email?("staff_shift_reminder", member)).to be(false)
    described_class::EMAILS_TOO.each { |key| expect(described_class.email?(key, member)).to be(true), key }
    expect(described_class.email?("shift_canceled", member.user)).to be(true)
  end

  it "lets the person's Email switch stop the time-critical ones" do
    member.user.set_notification_switches(email: { "shifts" => false })
    member.user.save!
    expect(described_class.email?("shift_canceled", member)).to be(false)
    expect(described_class.email?("staff_shift_removed", member)).to be(false)
    # Casting's switch is its own.
    expect(described_class.email?("show_canceled", member)).to be(true)
    # And no switch stops an email that is the point: a tax form, an invoice.
    member.user.set_notification_switches(email: { "pay" => false })
    member.user.save!
    expect(described_class.email?("staff_1099_ready", member)).to be(true)
  end

  it "names only templates that are notifications" do
    known = described_class::TEMPLATES.keys + described_class::VOICED.keys
    expect(described_class::EMAILS_TOO - known).to be_empty
    expect(described_class::EMAIL_AS_BEFORE - known).to be_empty
  end
end
