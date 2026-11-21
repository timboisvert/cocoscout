# frozen_string_literal: true

require "rails_helper"

# One place decides whether a new date starts with casting on (Tim,
# 2026-11-18): off when people aren't cast in the production; otherwise what
# its kind starts with. Every creator gets it from the model, and a caller
# that passes its own answer wins.
RSpec.describe Show, "a new date's casting" do
  let(:production) { create(:production) }

  def new_date(**attributes)
    create(:show, production: production, **attributes)
  end

  it "follows its kind while people are cast in the production" do
    expect(new_date(event_type: "show").casting_enabled).to be(true)
    expect(new_date(event_type: "class").casting_enabled).to be(true)
    expect(new_date(event_type: "workshop").casting_enabled).to be(true)
    expect(new_date(event_type: "open_mic").casting_enabled).to be(true)
    expect(new_date(event_type: "rehearsal").casting_enabled).to be(false)
    expect(new_date(event_type: "meeting").casting_enabled).to be(false)
  end

  it "starts off, whatever its kind, when people aren't cast in the production" do
    production.update!(casts_people: false)

    expect(new_date(event_type: "show").casting_enabled).to be(false)
    expect(new_date(event_type: "class").casting_enabled).to be(false)
  end

  # Which dates are cast is the production's choice, the one Ticketing
  # offers for which dates it sells: all performances, by event type, or
  # specific dates.
  it "is on only for the kinds of event the production casts, when it casts by event type" do
    production.update!(casting_event_matching: "event_types", casting_event_type_filter: %w[show rehearsal])

    expect(new_date(event_type: "show").casting_enabled).to be(true)
    expect(new_date(event_type: "rehearsal").casting_enabled).to be(true)
    expect(new_date(event_type: "class").casting_enabled).to be(false)
  end

  it "starts off, to be picked, when the production casts specific dates" do
    production.update!(casting_event_matching: "manual")

    expect(new_date(event_type: "show").casting_enabled).to be(false)
  end

  it "says what a new date starts with, truthfully for each choice" do
    expect(production.casting_dates_words).to eq("New shows, classes, workshops, and open mics start with casting on. Rehearsals and meetings start with it off.")

    production.update!(casting_event_matching: "event_types", casting_event_type_filter: %w[show rehearsal])
    expect(production.casting_dates_words).to eq("New shows and rehearsals start with casting on. Meetings, classes, workshops, and open mics start with it off.")

    production.update!(casting_event_type_filter: EventTypes.all)
    expect(production.casting_dates_words).to eq("Every new date starts with casting on.")

    production.update!(casting_event_matching: "manual")
    expect(production.casting_dates_words).to eq("A new date starts with casting off until you pick it.")

    production.update!(casts_people: false)
    expect(production.casting_dates_words).to eq("Every new date starts with casting off.")
  end

  it "keeps the answer a caller passed, either way" do
    expect(new_date(event_type: "rehearsal", casting_enabled: true).casting_enabled).to be(true)
    expect(new_date(event_type: "show", casting_enabled: false).casting_enabled).to be(false)

    production.update!(casts_people: false)
    expect(new_date(event_type: "show", casting_enabled: true).casting_enabled).to be(true)
  end

  it "never changes a date that already exists" do
    show = new_date(event_type: "show")
    production.update!(casts_people: false)

    show.update!(secondary_name: "Closing night")
    expect(show.reload.casting_enabled).to be(true)
  end

  describe ".casting_default_for" do
    it "keeps a copied date's own setting while people are cast in the production, and is off when they aren't" do
      rehearsal_with_casting = new_date(event_type: "rehearsal", casting_enabled: true)

      expect(described_class.casting_default_for(production, "rehearsal", like: rehearsal_with_casting)).to be(true)
      production.update!(casts_people: false)
      expect(described_class.casting_default_for(production, "rehearsal", like: rehearsal_with_casting)).to be(false)
    end
  end

  describe "a production's casting state" do
    it "is not set up until the questions are answered or a role is added, and off when people aren't cast in it" do
      expect(production.casting_state).to eq(:not_set_up)

      create(:role, production: production)
      expect(production.reload.casting_state).to eq(:on)

      production.update!(casts_people: false)
      expect(production.casting_state).to eq(:off)
    end
  end
end
