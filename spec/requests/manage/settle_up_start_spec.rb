# frozen_string_literal: true

require "rails_helper"

# Where Settle up starts (Tim, 2026-11-01): days before the start date are
# history, so the day 1.3 ships nobody opens Money to every show day they
# ever had. The deploy's one-time switch counts days already confirmed in
# Financials as settled, and posts nothing for them.
RSpec.describe "Settle up start date", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Holiday Revue") }

  def show_on(date, confirmed: false)
    create(:show, production: production, event_type: :show, date_and_time: date.in_time_zone.change(hour: 20)).tap do |s|
      create(:show_financials, show: s, ticket_revenue: 100.0, data_confirmed: confirmed) if confirmed
    end
  end

  def day_of(show) = SettlementDay.day_for(org, show.date_and_time)

  around { |ex| travel_to(Time.zone.local(2026, 11, 20, 12)) { ex.run } }

  it "converts: last month is history, this month's confirmed days count as settled, the rest stay to settle, nothing posts" do
    old = show_on(Date.new(2026, 10, 15))
    confirmed = show_on(Date.new(2026, 11, 5), confirmed: true)
    open_day = show_on(Date.new(2026, 11, 12))
    org.update_columns(settle_up_starts_on: nil)

    settled = SettleUpStart.convert!(org.reload)

    expect(settled).to eq(1)
    expect(org.reload.settle_up_starts_on).to eq(Date.new(2026, 11, 1))
    record = SettlementDay.find_by!(organization: org, date: day_of(confirmed))
    expect(record).to be_settled
    expect(record.notes).to eq(SettleUpStart::NOTE)
    expect(JournalEntry.where(organization_id: org.id, kind: "settlement")).to be_empty
    expect(SettleUp.to_settle(org).map(&:date)).to eq([ day_of(open_day) ])
    expect(SettleUp.to_settle(org).map(&:date)).not_to include(day_of(old))
  end

  it "shows a history day read only, refuses changes to it, and lets the owner move the start" do
    old = show_on(Date.new(2026, 10, 15))
    org.update_columns(settle_up_starts_on: Date.new(2026, 11, 1))
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path

    get manage_money_index_path
    expect(response.body).to include("Every day is settled.")

    get manage_money_settle_up_day_path(day_of(old).iso8601)
    expect(response.body).to include("Before Settle up", "is before Settle up started", "Change the start date")
    expect(response.body).not_to include("Mark the day settled")

    patch manage_check_show_money_settle_up_day_path(day_of(old).iso8601, show_id: old.id), params: { checked: "1" }
    expect(flash[:alert]).to include("before Settle up started")
    expect(old.reload.show_financials&.data_confirmed).to be_falsey

    # Moving it earlier brings the day back to settle; a future date stops at today.
    patch manage_money_settings_settle_up_path, params: { settlement_day_mode: "smart", settlement_day_starts_at: "6", settle_up_starts_on: "2026-10-01" }
    expect(org.reload.settle_up_starts_on).to eq(Date.new(2026, 10, 1))
    expect(SettleUp.to_settle(org).map(&:date)).to include(day_of(old))
    patch manage_money_settings_settle_up_path, params: { settlement_day_mode: "smart", settlement_day_starts_at: "6", settle_up_starts_on: "2027-01-01" }
    expect(org.reload.settle_up_starts_on).to eq(Date.new(2026, 11, 20))

    get manage_money_settings_section_path(section: "settle_up")
    expect(response.body).to include("Where Settle up starts", "Settle up starts on")
  end
end
