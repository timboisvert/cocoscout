# frozen_string_literal: true

require "rails_helper"

# Destroying a Show whose revenue-share ContractPayment references it used to
# trip the contract_payments→shows FK: the show's ShowFinancials after_destroy
# fires the contract-payment sync mid-destroy — after dependent: :nullify has
# run but before the show's own DELETE, while show.destroyed? is still false —
# and find_payment_for_show writes show_id back onto the payment "for future
# lookups". Every destroy site must unlink referencing payments and destroy
# inside Show.without_contract_payment_sync (same treatment as
# Contract#cancel!, #apply_amendment! and ContractDateChanges).
RSpec.describe "Deleting shows under revenue-share contracts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }
  let!(:contract) { create(:contract, :active, :revenue_share_per_event, organization: org, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def build_show!(date_and_time, recurrence_group_id: nil)
    show = production.shows.create!(date_and_time: date_and_time, duration_minutes: 120,
                                    location: location, recurrence_group_id: recurrence_group_id)
    show.create_show_financials!(ticket_revenue: 500, ticket_count: 40)
    show
  end

  def build_payment!(show, status: "pending")
    contract.contract_payments.create!(description: "Revenue Share", amount: 100,
                                       direction: "incoming", due_date: show.date_and_time.to_date,
                                       status: status, show_id: show.id)
  end

  describe "shows#delete_show" do
    it "deletes a show with a pending payment and drops the payment with it" do
      show = build_show!(2.weeks.from_now.change(hour: 20))
      payment = build_payment!(show)

      delete manage_delete_show_path(production, show)

      expect(response).to redirect_to(manage_production_shows_path(production))
      expect(Show.exists?(show.id)).to be(false)
      expect(ContractPayment.exists?(payment.id)).to be(false)
      expect(flash[:notice]).to include("pending contract payment")
    end

    it "deletes a show with a paid payment, unlinking but keeping the payment" do
      show = build_show!(2.weeks.from_now.change(hour: 20))
      payment = build_payment!(show, status: "paid")

      delete manage_delete_show_path(production, show)

      expect(response).to redirect_to(manage_production_shows_path(production))
      expect(Show.exists?(show.id)).to be(false)
      expect(payment.reload.show_id).to be_nil
    end

    it "deletes a whole recurring series with linked payments" do
      group_id = SecureRandom.uuid
      shows = [ 2.weeks.from_now, 3.weeks.from_now ].map do |t|
        build_show!(t.change(hour: 20), recurrence_group_id: group_id)
      end
      paid = build_payment!(shows.first, status: "paid")
      pending = build_payment!(shows.last)

      delete manage_delete_show_path(production, shows.first, scope: "all")

      expect(response).to redirect_to(manage_production_shows_path(production))
      expect(Show.where(id: shows.map(&:id))).to be_empty
      expect(paid.reload.show_id).to be_nil
      expect(ContractPayment.exists?(pending.id)).to be(false)
    end
  end

  describe "shows#update (recreate recurring series)" do
    it "rebuilds the series even when a payment references a show, keeping pending payments" do
      group_id = SecureRandom.uuid
      start = 2.weeks.from_now.change(hour: 20)
      show = build_show!(start, recurrence_group_id: group_id)
      build_show!(start + 1.week, recurrence_group_id: group_id)
      payment = build_payment!(show)

      patch manage_update_show_path(production, show), params: {
        show: {
          recurrence_edit_scope: "all",
          recurrence_pattern: "weekly",
          recurrence_start_datetime: start.iso8601,
          recurrence_end_date: (start + 2.weeks).to_date.iso8601
        }
      }

      expect(response).to redirect_to(manage_production_shows_path(production))
      expect(Show.exists?(show.id)).to be(false)
      expect(payment.reload.show_id).not_to eq(show.id)
      expect(production.shows.where(recurrence_group_id: group_id).count).to eq(3)
    end
  end

  describe "productions#destroy" do
    it "deletes a third-party production whose shows carry linked payments" do
      show = build_show!(2.weeks.from_now.change(hour: 20))
      payment = build_payment!(show, status: "paid")

      get manage_production_path(production) # seeds the current-production session key
      delete manage_production_path(production)

      expect(response).to redirect_to(manage_productions_path)
      expect(Production.exists?(production.id)).to be(false)
      expect(Show.exists?(show.id)).to be(false)
      expect(payment.reload.show_id).to be_nil
      expect(contract.reload.production_id).to be_nil
    end
  end
end
