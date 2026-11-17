# frozen_string_literal: true

require "rails_helper"

# A contractor's request about one contract date: asking, the two answers,
# and closing itself when the date comes to say what was asked.
RSpec.describe ContractDateRequests do
  let!(:owner) { create(:user) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user) }
  let!(:contractor) { create(:contractor, organization: org, person: person) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor,
                               contractor_name: "Thea", contractor_email: contractor.email)
  end
  let!(:location) { create(:location, organization: org) }
  let(:night) { 1.month.from_now.change(hour: 20, min: 0) }
  let!(:rental) { create(:space_rental, contract: contract, location: location, starts_at: night, ends_at: night + 2.hours) }
  let!(:show) { production.shows.create!(date_and_time: night, duration_minutes: 120, location: location, space_rental: rental) }

  before { org.update!(contract_notification_user_ids: [ owner.id ]) }

  def ask(kind: "move", proposed_at: night - 30.minutes, note: nil, about: show)
    described_class.ask!(contract: contract, user: user, show: about, kind: kind, proposed_at: proposed_at, note: note)
  end

  describe ".ask!" do
    it "records the request and notifies the organization's contract people" do
      request = nil
      expect { request = ask(note: "We agreed on 7:30.") }.to change(owner.notifications, :count).by(1)

      expect(request).to have_attributes(status: "open", kind: "move", original_at: show.date_and_time, organization: org)
      notification = owner.notifications.last
      expect(notification.title).to start_with("#{contract.contractor_name} requests to move ")
      expect(notification.path).to eq("/manage/contracts/#{contract.to_param}")
      expect(notification.category).to eq("contracts")
    end

    it "changes nothing on the contract" do
      expect { ask }.not_to(change { [ show.reload.date_and_time, rental.reload.starts_at ] })
    end

    it "keeps one waiting request per date: asking again takes the first back" do
      first = ask
      second = ask(proposed_at: night - 1.hour)

      expect(first.reload.status).to eq("withdrawn")
      expect(contract.date_requests.waiting).to contain_exactly(second)
    end

    it "is the contractor's alone" do
      stranger = create(:user)
      create(:person, user: stranger)

      expect { described_class.ask!(contract: contract, user: stranger, show: show, kind: "cancel") }
        .to raise_error(described_class::NotAllowed)
    end

    it "won't ask about a date that isn't this contract's" do
      other_production = create(:production, organization: org)
      other_show = other_production.shows.create!(date_and_time: night, duration_minutes: 60, location: location)

      expect { ask(about: other_show) }.to raise_error(described_class::NotAllowed)
    end

    it "says why a request can't be asked" do
      expect { ask(proposed_at: nil) }.to raise_error(ActiveRecord::RecordInvalid, /Choose the day and time/)
      expect { ask(proposed_at: night) }.to raise_error(ActiveRecord::RecordInvalid, /already is/)
      expect { ask(kind: "question") }.to raise_error(ActiveRecord::RecordInvalid, /Write your question/)
    end

    it "asks to add a date with no date of the contract's behind it" do
      request = ask(kind: "add", about: nil, proposed_at: night + 1.day)

      expect(request).to have_attributes(kind: "add", show: nil, status: "open")
      expect(request.words).to start_with("add ")
    end
  end

  describe ".keep!" do
    it "answers no with a note and notifies whoever asked" do
      request = ask

      expect { described_class.keep!(request, user: owner, note: "Doors are 7:30, the show is 8.") }
        .to change(user.notifications, :count).by(1)
      expect(request.reload).to have_attributes(status: "kept", answered_by: owner, answer_note: "Doors are 7:30, the show is 8.")
      expect(user.notifications.last.title).to include(org.name).and include("kept")
      expect(user.notifications.last.path).to eq("/my/contracts")
    end

    it "answers a request once" do
      request = ask
      described_class.keep!(request, user: owner)

      expect { described_class.keep!(request.reload, user: owner, note: "again") }.not_to change(user.notifications, :count)
      expect(request.reload.answer_note).to be_nil
    end
  end

  describe "closing itself" do
    it "is done when the date moves to what was asked, however it moved" do
      request = ask(proposed_at: night - 30.minutes)

      expect { ContractDateChanges.move!(contract: contract, rental: rental, starts_at: night - 30.minutes, ends_at: night + 90.minutes) }
        .to change(user.notifications, :count).by(1)
      expect(request.reload.status).to eq("done")
      expect(user.notifications.last.title).to include("as you requested")
    end

    it "no longer applies when the date moves somewhere else" do
      request = ask(proposed_at: night - 30.minutes)

      expect { ContractDateChanges.move!(contract: contract, rental: rental, starts_at: night + 1.hour, ends_at: night + 3.hours) }
        .not_to change(user.notifications, :count)
      expect(request.reload.status).to eq("void")
    end

    it "is done when a date they asked to cancel comes off the contract" do
      request = ask(kind: "cancel", proposed_at: nil)

      ContractDateChanges.remove!(contract: contract, rental: rental)

      expect(request.reload).to have_attributes(status: "done", show_id: nil)
      expect(request.outcome_words).to start_with("canceled ")
    end

    it "leaves a question open through a change of time" do
      request = ask(kind: "question", proposed_at: nil, note: "Is load-in at 5?")

      ContractDateChanges.move!(contract: contract, rental: rental, starts_at: night + 1.hour, ends_at: night + 3.hours)

      expect(request.reload.status).to eq("open")
    end
  end

  describe ".staged!" do
    it "marks a request an amendment answers as waiting on the contractor's signature" do
      request = ask(proposed_at: night - 30.minutes)
      amend = { "moved_rentals" => { rental.id.to_s => { "starts_at" => (night - 30.minutes).iso8601, "ends_at" => (night + 90.minutes).iso8601 } } }

      expect { described_class.staged!(contract, amend, by: owner) }.to change(user.notifications, :count).by(1)
      expect(request.reload).to have_attributes(status: "amending", answered_by: owner)
    end

    it "leaves alone a request the amendment doesn't answer" do
      request = ask(proposed_at: night - 30.minutes)
      amend = { "moved_rentals" => { rental.id.to_s => { "starts_at" => (night + 1.hour).iso8601, "ends_at" => (night + 3.hours).iso8601 } } }

      described_class.staged!(contract, amend, by: owner)

      expect(request.reload.status).to eq("open")
    end
  end

  describe ".amend_prefill" do
    it "moves the whole night by as much as the show was asked to" do
      request = ask(proposed_at: night - 30.minutes)

      prefill = described_class.amend_prefill(request)

      expect(prefill[rental.id]).to include(action: "move")
      expect(prefill[rental.id][:times]).to include(starts_at: night - 30.minutes, ends_at: night + 90.minutes)
    end

    it "starts a cancel on Remove" do
      expect(described_class.amend_prefill(ask(kind: "cancel", proposed_at: nil))).to eq(rental.id => { action: "remove" })
    end
  end

  describe ".sweep!" do
    it "reminds the organization once, three days in" do
      request = ask
      request.update_columns(created_at: 4.days.ago)

      expect { described_class.sweep! }.to change(owner.notifications, :count).by(1)
      expect(owner.notifications.last.title).to include("still waiting")
      expect { described_class.sweep! }.not_to change(owner.notifications, :count)
    end

    it "closes a request whose date has passed" do
      request = ask
      show.update_columns(date_and_time: 1.day.ago)

      described_class.sweep!

      expect(request.reload.status).to eq("void")
    end
  end
end
