# frozen_string_literal: true

require "rails_helper"

# An event's name is something somebody chose and we stored, not a string
# re-derived on every screen. The forms pre-fill Show Name with a suggestion
# built from the production and the event type; a show still carrying that
# suggestion follows the production and its own event type when either changes,
# and never prints as a subtitle under the production name it repeats.
RSpec.describe "Show names", type: :model do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization, name: "Improv Jam") }

  def show_for(event_type: "show", secondary_name: nil, prod: production)
    create(:show, production: prod, event_type: event_type, secondary_name: secondary_name,
                  date_and_time: Time.zone.local(2026, 9, 18, 20, 0))
  end

  describe ".suggested_name" do
    it "pairs the production name with the kind of night" do
      expect(Show.suggested_name(production_name: "Improv Jam", event_type: "rehearsal"))
        .to eq("Improv Jam Rehearsal")
    end

    it "leaves a third-party production's own name alone" do
      expect(Show.suggested_name(production_name: "Touring Act", event_type: "show", third_party: true))
        .to eq("Touring Act")
    end

    it "falls back to a bare word with no production to name" do
      expect(Show.suggested_name(production_name: nil, event_type: "show")).to eq("Show")
    end
  end

  describe "#display_name" do
    it "uses the stored name when there is one" do
      expect(show_for(secondary_name: "Opening Night").display_name).to eq("Opening Night")
    end

    it "falls back to the suggestion for a show created before events were named" do
      expect(show_for.display_name).to eq("Improv Jam Show")
    end
  end

  describe "#name_subtitle" do
    it "is nil while the show is just carrying its suggested name" do
      expect(show_for(secondary_name: "Improv Jam Show").name_subtitle).to be_nil
    end

    it "is nil when the show was never named" do
      expect(show_for.name_subtitle).to be_nil
    end

    it "is the name when somebody chose one" do
      expect(show_for(secondary_name: "Opening Night").name_subtitle).to eq("Opening Night")
    end
  end

  describe "following the event type" do
    it "renames an auto-named show when its kind changes" do
      show = show_for(event_type: "rehearsal", secondary_name: "Improv Jam Rehearsal")

      show.update!(event_type: "show")

      expect(show.reload.secondary_name).to eq("Improv Jam Show")
    end

    it "leaves a name somebody typed alone" do
      show = show_for(event_type: "rehearsal", secondary_name: "Tech Run")

      show.update!(event_type: "show")

      expect(show.reload.secondary_name).to eq("Tech Run")
    end
  end

  describe "following a production rename" do
    it "carries auto-named shows over to the new name" do
      auto = show_for(secondary_name: "Improv Jam Show")
      rehearsal = show_for(event_type: "rehearsal", secondary_name: "Improv Jam Rehearsal")
      chosen = show_for(secondary_name: "Opening Night")

      production.update!(name: "Jam Night")

      expect(auto.reload.secondary_name).to eq("Jam Night Show")
      expect(rehearsal.reload.secondary_name).to eq("Jam Night Rehearsal")
      expect(chosen.reload.secondary_name).to eq("Opening Night")
    end

    it "leaves shows alone when something other than the name changes" do
      auto = show_for(secondary_name: "Improv Jam Show")

      expect { production.update!(description: "Weekly chaos") }
        .not_to change { auto.reload.secondary_name }
    end
  end
end
