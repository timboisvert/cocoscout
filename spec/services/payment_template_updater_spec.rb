# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTemplateUpdater do
  describe ".apply!" do
    it "creates the payment_setup_nudge template when absent" do
      expect { described_class.apply! }
        .to change { ContentTemplate.exists?(key: "payment_setup_nudge") }.from(false).to(true)

      nudge = ContentTemplate.find_by(key: "payment_setup_nudge")
      expect(nudge.channel).to eq("message")
      expect(nudge.active?).to be(true)
      expect(nudge.body).to include("{{payment_setup_url}}")
    end

    it "is idempotent — a second run leaves the nudge as-is and adds nothing" do
      described_class.apply!
      log = nil
      expect { log = described_class.apply! }.not_to change(ContentTemplate, :count)
      expect(log).to include(a_string_matching(/payment_setup_nudge: already present/))
    end

    it "treats a lost create race as 'already present' instead of raising" do
      # Isolate the nudge path: no reminder present means refresh_reminders!
      # takes the skip branch and never calls save!, so the stub below only
      # affects the nudge create.
      ContentTemplate.where(key: "payment_setup_reminder").delete_all
      # Simulate a multi-host deploy where another host inserts the row between
      # our find_or_initialize and our save!, tripping the unique index.
      allow_any_instance_of(ContentTemplate).to receive(:save!)
        .and_raise(ActiveRecord::RecordNotUnique.new("key already taken"))

      log = nil
      expect { log = described_class.apply! }.not_to raise_error
      expect(log).to include(a_string_matching(/payment_setup_nudge: already present \(created concurrently\)/))
    end

    it "removes Venmo/Zelle wording from an existing reminder, in place" do
      reminder = ContentTemplate.where(key: "payment_setup_reminder").first_or_initialize
      reminder.update!(
        name: "Reminder", category: "payments", channel: "email", template_type: "hybrid", active: true,
        subject: "Set up your Venmo or Zelle",
        body: "<p>Please add your Venmo or Zelle details so we can pay you.</p>",
        description: "For Venmo/Zelle payouts"
      )

      described_class.apply!
      reminder.reload
      expect(reminder.subject).to eq("Set up your bank account")
      expect(reminder.body).to include("bank account")
      expect(reminder.body).not_to include("Venmo")
      expect(reminder.description).not_to include("Venmo")
    end

    it "reports the reminder as skipped when it isn't present in this environment" do
      ContentTemplate.where(key: "payment_setup_reminder").delete_all
      expect(described_class.apply!).to include("payment_setup_reminder: not present (skipped)")
    end
  end
end
