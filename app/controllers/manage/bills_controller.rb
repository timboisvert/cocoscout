# frozen_string_literal: true

module Manage
  # Money → Bills (plan D1): what the organization owes and hasn't paid,
  # a bill's page with Mark paid, Add a bill. Bills and invoices access, by
  # the grid; changing needs manage.
  class BillsController < Manage::ManageController
    before_action :set_bill, only: %i[show edit update pay void]
    before_action :require_change!, only: %i[new create edit update pay void]
    before_action :load_choices, only: %i[new create edit update]

    def index
      @filter = params[:filter].presence_in(%w[to_pay paid all]) || "to_pay"
      @production_id = Current.organization.productions.find_by(id: params[:production])&.id
      @productions = Current.organization.productions.active.order(:name)
      scope = Current.organization.bills.includes(:production).by_due
      scope = scope.where(production_id: @production_id) if @production_id
      @open = scope.open.to_a
      @owed_cents = @open.sum(&:unpaid_cents)
      today = Date.current
      @groups = [
        [ "Overdue", @open.select { |b| b.due_on < today }, "text-red-700" ],
        [ "Due this week", @open.select { |b| b.due_on >= today && b.due_on < today + 7 }, "text-gray-500" ],
        [ "Later", @open.select { |b| b.due_on >= today + 7 }, "text-gray-500" ]
      ].reject { |_, rows, _| rows.empty? }
      @repeats = scope.open.where.not(repeats: "none").to_a
      @paid = (@filter == "to_pay" ? scope.paid.where(paid_on: today.beginning_of_month..today.end_of_month) : scope.paid).reorder(paid_on: :desc, id: :desc).limit(@filter == "to_pay" ? 8 : 200).to_a
    end

    def show
      @payments = @bill.bill_payments.order(:on, :id)
    end

    def new
      @bill = Current.organization.bills.new(issued_on: Date.current, due_on: Date.current + 14, repeats: "none")
    end

    def create
      @bill = Current.organization.bills.new(bill_params.merge(created_by: Current.user))
      if @bill.save
        redirect_to manage_money_bill_path(@bill), notice: "Added. #{@bill.vendor_name}, #{helpers.number_to_currency(@bill.amount)}, due #{@bill.due_on.strftime('%b %-d')}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @bill.update(bill_params)
        redirect_to manage_money_bill_path(@bill), notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Mark paid: the date, the amount (part or whole), how.
    def pay
      return redirect_to manage_money_bill_path(@bill), alert: "This bill is #{@bill.status}." unless @bill.open?

      cents = (params[:amount].to_s.delete("$,").to_f * 100).round
      cents = @bill.unpaid_cents if cents <= 0
      on = Date.parse(params[:on].presence || Date.current.iso8601) rescue Date.current
      @bill.pay!(on: on, amount_cents: cents, via: params[:via].presence_in(Bill::VIA.keys) || "bank", by: Current.user, reference: params[:reference].presence, memo: params[:memo].presence)
      notice = @bill.reload.paid? ? "Paid. #{@bill.vendor_name} is settled#{@bill.repeats == 'none' ? '' : ', and the next one is on the list'}." : "#{helpers.number_to_currency(cents / 100.0)} paid; #{helpers.number_to_currency(@bill.reload.unpaid_cents / 100.0)} still to go."
      redirect_to manage_money_bill_path(@bill), notice: notice
    end

    def void
      @bill.void!(params[:reason])
      redirect_to manage_money_bills_path, notice: "Cancelled. The bill comes off the books; it stays on its page for the record."
    end

    private

    def set_bill
      @bill = Current.organization.bills.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :bills_invoices, :manage)

      redirect_to manage_money_bills_path, alert: "You can look at bills but not change them."
    end

    def load_choices
      @productions = Current.organization.productions.active.order(:name)
      @shows = Show.where(production_id: @productions.map(&:id), canceled: false).order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
    end

    def bill_params
      params.require(:bill).permit(:vendor_name, :vendor_email, :vendor_reference, :amount, :issued_on, :due_on, :category_key, :production_id, :show_id, :memo, :repeats, :document)
    end
  end
end
