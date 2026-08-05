# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutSentPayeeNotificationJob, type: :job do
  let(:org) { create(:organization, :pro, name: "Stars and Garters") }
  let(:batch) do
    create(:payout_batch, organization: org, kind: "staff_pay", status: "funding",
                          funding_status: "processing", payday: Date.current)
  end

  # Bank connected, so they get a real deposit window.
  def connected_person(name: "Allison Abrams", with_user: true)
    create(:person, name: name, stripe_account_id: "acct_#{SecureRandom.hex(4)}", payouts_enabled: true).tap do |p|
      p.update!(user: create(:user)) if with_user
    end
  end

  def item_for(payee, cents: 15_000, batch: nil)
    (batch || self.batch).items.create!(payee: payee, amount_cents: cents, status: "pending")
  end

  # The plain-text part of the email, decoded. Must be decoded rather than read
  # off .encoded: quoted-printable line-wraps longer sentences mid-phrase, so
  # substring assertions against the raw MIME envelope silently fail.
  def last_email_body
    mail = ActionMailer::Base.deliveries.last
    (mail.text_part || mail.html_part || mail).body.decoded
  end

  before { ActionMailer::Base.deliveries.clear }

  describe "who gets told" do
    it "emails and messages each Person payee, then stamps them as notified" do
      person = connected_person
      item = item_for(person)

      expect { described_class.perform_now(batch.id) }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ person.email ])
      expect(mail.subject).to include("$150.00").and include("Stars and Garters")
      expect(item.reload.payee_notified_at).to be_present

      message = Message.order(:created_at).last
      expect(message.message_recipients.map(&:recipient)).to eq([ person ])
      expect(message).to be_automated
    end

    it "never notifies the same payee twice for one run" do
      item_for(connected_person)
      described_class.perform_now(batch.id)

      # pay_remaining! and the course executor are both re-runnable.
      expect { described_class.perform_now(batch.id) }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "skips an Organization payee — that's the org paying itself" do
      org.update!(stripe_account_id: "acct_org", payouts_enabled: true)
      item_for(org)

      expect { described_class.perform_now(batch.id) }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "notifies the Person behind a Contractor" do
      person = connected_person(name: "Dan Feltey")
      contractor = create(:contractor, organization: org, person: person)
      item_for(contractor)

      described_class.perform_now(batch.id)

      expect(ActionMailer::Base.deliveries.last.to).to eq([ person.email ])
    end

    it "still emails a payee who has no login, even though the in-app message can't reach them" do
      person = connected_person(with_user: false)
      item_for(person)

      messages_before = Message.count
      expect { described_class.perform_now(batch.id) }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(Message.count).to eq(messages_before)
    end

    it "does not promise money on a run whose funding failed" do
      item_for(connected_person)
      batch.update!(status: "failed", funding_status: "failed")

      expect { described_class.perform_now(batch.id) }
        .not_to change { ActionMailer::Base.deliveries.size }
    end

    it "keeps paying out the rest of the run when one payee's email blows up" do
      boom = connected_person(name: "Boom Person")
      fine = connected_person(name: "Fine Person")
      item_for(boom)
      item_for(fine)

      allow(PayoutBatchMailer).to receive(:sent_to_payee).and_wrap_original do |orig, **kwargs|
        raise "SMTP exploded" if kwargs[:person] == boom
        orig.call(**kwargs)
      end

      expect { described_class.perform_now(batch.id) }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ fine.email ])
    end
  end

  describe "which story the payee is told" do
    it "gives a returning payee the normal 2–4 business day window" do
      person = connected_person
      # An earlier payment, so they're not a first-timer.
      create(:payout_batch, organization: org, kind: "staff_pay", status: "completed")
        .items.create!(payee: person, amount_cents: 500, status: "paid", paid_at: 1.month.ago)
      item_for(person)

      described_class.perform_now(batch.id)

      earliest, latest = batch.expected_deposit_range
      expect(last_email_body).to include("on its way to your bank")
        .and include(earliest.strftime("%B %-d"))
        .and include(latest.strftime("%B %-d, %Y"))
      expect(last_email_body).not_to include("first payment")
    end

    it "warns a first-timer that the first one takes longer, without naming our provider" do
      item_for(connected_person)

      described_class.perform_now(batch.id)

      body = last_email_body
      expect(body).to include("first payment through CocoScout").and include("our payout provider")
      expect(body).not_to match(/stripe/i)

      # The longer window, not the 2–4 day one.
      first_earliest, first_latest = batch.expected_deposit_range(first_payout: true)
      expect(body).to include(first_earliest.strftime("%B %-d")).and include(first_latest.strftime("%B %-d, %Y"))
      expect(first_earliest).to eq(batch.payday + 7.days)
      expect(first_latest).to eq(batch.payday + 14.days)
    end

    it "tells a payee with no bank that the money is set aside, not on its way" do
      person = create(:person, name: "Nobank Nel", user: create(:user))
      item_for(person)

      described_class.perform_now(batch.id)

      expect(last_email_body).to include("set aside for you").and include("haven't connected a bank")
      expect(last_email_body).not_to include("on its way to your bank")
      # The subject must not contradict the body by promising a deposit.
      expect(ActionMailer::Base.deliveries.last.subject).to eq("$150.00 from Stars and Garters is waiting for you")
    end

    # The subject is built entirely from conditional blocks, so a missing flag
    # would ship an email with no subject line at all.
    it "always produces a subject, whichever story is told" do
      item_for(connected_person(name: "Connected Person"))
      item_for(create(:person, name: "Nobank Person"))

      described_class.perform_now(batch.id)

      expect(ActionMailer::Base.deliveries.size).to eq(2)
      ActionMailer::Base.deliveries.each do |mail|
        expect(mail.subject).to be_present
        expect(mail.subject).not_to include("{{")
      end
    end

    it "keeps the plain-text part readable instead of running the sentences together" do
      item_for(connected_person)

      described_class.perform_now(batch.id)

      expect(last_email_body).to include("Hi Allison,\n")
      expect(last_email_body).not_to match(/Hi Allison,\$/)
    end
  end

  describe "first-timer detection" do
    let(:person) { connected_person }

    it "treats a payee already paid by a different organization as a returning payee" do
      other_org = create(:organization, :pro)
      create(:payout_batch, organization: other_org, kind: "performer", status: "completed")
        .items.create!(payee: person, amount_cents: 900, status: "paid", paid_at: 2.weeks.ago)
      item_for(person)

      described_class.perform_now(batch.id)

      expect(last_email_body).not_to include("first payment")
    end

    it "still treats a payee as a first-timer when their only history was paid another way" do
      # Offline payments never reach the payout account, so the provider's
      # first-payout hold still applies.
      show = create(:show, production: create(:production, organization: org))
      payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 40)
      ShowPayoutLineItem.create!(show_payout: payout, payee: person, amount: 40,
                                 manually_paid: true, paid_at: 1.month.ago, payment_method: "cash")
      item_for(person)

      described_class.perform_now(batch.id)

      expect(last_email_body).to include("first payment through CocoScout")
    end

    it "does not count the payment it is currently announcing (course runs transfer first)" do
      course_batch = create(:payout_batch, organization: org, kind: "course", status: "completed", payday: Date.current)
      course_batch.items.create!(payee: person, amount_cents: 8_000, status: "paid", paid_at: Time.current)

      described_class.perform_now(course_batch.id)

      expect(last_email_body).to include("first payment through CocoScout")
    end
  end
end
