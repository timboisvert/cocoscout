# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Availability calendar", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:pool) { create(:talent_pool, production: production) }

  before do
    TalentPoolMembership.create!(talent_pool: pool, member: person)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  # Display utilities that are defined AFTER `.hidden` in the built Tailwind
  # CSS, so they beat `display:none` when both land on one element. Verified
  # against app/assets/builds/tailwind.css: .flex/.grid sort before .hidden
  # (safe — that's how every modal hides), .inline* and .table sort after.
  OVERRIDES_HIDDEN = %w[inline inline-block inline-flex table].freeze

  # Class attributes in the response where a bare `hidden` is cancelled out by
  # one of those. Prefixed variants (sm:hidden, lg:flex) are intentional and
  # live in media queries, so only bare class names count.
  def classes_that_cannot_hide(body)
    body.scan(/class="([^"]*)"/).flatten.select do |classes|
      names = classes.split(/\s+/)
      names.include?("hidden") && names.any? { |n| OVERRIDES_HIDDEN.include?(n) }
    end
  end

  it "renders read-only day tiles with a status chip and an editable day modal using the standard rows" do
    show = create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19, min: 30))
    create(:show_availability, :available, show: show, available_entity: person)
    unanswered = create(:show, production: production, date_and_time: 12.days.from_now)

    get my_availability_calendar_path
    expect(response).to have_http_status(:ok)

    # Desktop tiles: status chips, no inline thumbs buttons
    expect(response.body).to include("Available")
    expect(response.body).to include("Needs response")
    expect(response.body).not_to include("M6.633 10.25") # old thumb SVG path

    # A tile renders all three status chips so the answer can swap live without
    # a reload. Only the current one may show — but `hidden` (display:none)
    # loses to any display utility that sorts after it in the built Tailwind
    # CSS, so an element carrying both `hidden` and `inline-flex`/`flex`/`grid`
    # stays visible no matter what the markup intends. That's exactly how all
    # three chips once rendered at once; guard the invariant, not the classes.
    conflicted = classes_that_cannot_hide(response.body)
    expect(conflicted).to be_empty,
      "these elements ask to hide but set a display that overrides it: #{conflicted.inspect}"

    # Day cells open modals; the modal holds the standard availability row
    expect(response.body).to include("day-modal-#{show.date_and_time.to_date.iso8601}")
    expect(response.body).to include("day-modal-#{unanswered.date_and_time.to_date.iso8601}")
    expect(response.body).to include("availability#setStatus")
    expect(response.body).to include("request-item-#{show.id}-person_#{person.id}")
  end
end
