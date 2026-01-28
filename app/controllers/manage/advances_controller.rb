# frozen_string_literal: true

module Manage
  class AdvancesController < ManageController
    before_action :set_production
    before_action :set_advance, only: %i[show update destroy write_off mark_paid unmark_paid]
    before_action :set_waiver, only: %i[destroy_waiver]

    def index
      if @production
        load_production_advances
      else
        load_org_advances
      end
    end

    def new
      @advance = @production.person_advances.build(advance_type: "show")
      @upcoming_shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time).limit(30)
      @people = fetch_production_people
    end

    def create
      @advance = @production.person_advances.build(advance_params)
      @advance.issued_by = Current.user
      @advance.issued_at = Time.current
      @advance.remaining_balance = @advance.original_amount

      if @advance.save
        redirect_to manage_money_production_advances_path(@production),
                    notice: "Advance of #{helpers.number_to_currency(@advance.original_amount)} issued to #{@advance.person.name}."
      else
        @upcoming_shows = @production.shows.upcoming.order(:date_and_time).limit(30)
        @people = fetch_production_people
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @repayments = @advance.advance_applications.includes(show_payout_line_item: { show_payout: :show }).order(:created_at)
    end

    def update
      if @advance.update(advance_update_params)
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      notice: "Advance updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      if @advance.unpaid?
        @advance.destroy
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      notice: "Advance cancelled."
      else
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      alert: "Cannot delete an advance that has already been paid."
      end
    end

    def write_off
      notes = params[:notes]

      if @advance.write_off!(notes: notes)
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      notice: "Advance written off. Remaining balance of #{helpers.number_to_currency(@advance.remaining_balance)} has been forgiven."
      else
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      alert: "Could not write off advance."
      end
    end

    def mark_paid
      method = params[:payment_method] || "venmo"
      notes = params[:notes]

      @advance.mark_paid!(Current.user, method: method, notes: notes)

      respond_to do |format|
        format.html { redirect_back fallback_location: manage_money_production_advances_path(@production), notice: "Advance marked as paid." }
        format.turbo_stream
      end
    end

    def unmark_paid
      @advance.unmark_paid!

      respond_to do |format|
        format.html { redirect_back fallback_location: manage_money_production_advances_path(@production), notice: "Advance unmarked as paid." }
        format.turbo_stream
      end
    end

    # Waivers - for recording why someone didn't get an advance
    def create_waiver
      @waiver = ShowAdvanceWaiver.new(waiver_params)
      @waiver.waived_by = Current.user

      if @waiver.save
        respond_to do |format|
          format.html { redirect_back fallback_location: manage_money_production_advances_path(@production), notice: "Waiver recorded." }
          format.turbo_stream { render turbo_stream: turbo_stream.remove("advance_eligible_#{@waiver.show_id}_#{@waiver.person_id}") }
        end
      else
        redirect_back fallback_location: manage_money_production_advances_path(@production),
                      alert: @waiver.errors.full_messages.join(", ")
      end
    end

    def destroy_waiver
      @waiver.destroy
      redirect_back fallback_location: manage_money_production_advances_path(@production),
                    notice: "Waiver removed."
    end

    private

    def set_production
      if params[:production_id].present?
        @production = Current.organization.productions.find(params[:production_id])
      else
        @production = nil
      end
    end

    def set_advance
      @advance = @production.person_advances.find(params[:id])
    end

    def set_waiver
      @waiver = ShowAdvanceWaiver.find(params[:id])
    end

    def advance_params
      params.require(:person_advance).permit(:person_id, :show_id, :original_amount, :advance_type, :notes)
    end

    def advance_update_params
      params.require(:person_advance).permit(:notes)
    end

    def waiver_params
      params.require(:show_advance_waiver).permit(:show_id, :person_id, :reason, :notes)
    end

    def fetch_production_people
      # Get people from talent pool
      if @production.talent_pool
        @production.talent_pool.talent_pool_memberships.where(member_type: "Person").includes(:member).map(&:member).compact
      else
        []
      end
    end

    def load_production_advances
      base_scope = @production.person_advances

      # Split outstanding advances into unpaid (we owe them) and paid (they owe us)
      all_outstanding = base_scope.outstanding.includes(:person, :show, :issued_by).by_issued_at
      @unpaid_advances = all_outstanding.unpaid
      @outstanding_advances = all_outstanding.paid
      @repaid_advances = base_scope.fully_recovered.includes(:person, :show, :issued_by).by_issued_at.limit(50)
      @written_off_advances = base_scope.written_off.includes(:person, :show, :issued_by).by_issued_at.limit(20)

      # Summary stats
      @total_unpaid = @unpaid_advances.sum(:original_amount)
      @total_outstanding = @outstanding_advances.sum(:remaining_balance)
      @total_issued_this_month = base_scope.where("issued_at >= ?", Date.current.beginning_of_month).sum(:original_amount)

      # For the new advance form
      @upcoming_shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time).limit(20)
      @people = @production.talent_pool&.talent_pool_memberships&.where(member_type: "Person")&.includes(:member)&.map(&:member) || []
    end

    def load_org_advances
      # Load non-third-party productions
      @productions = Current.organization.productions.where.not(production_type: "third_party").order(:name)

      # Build summary for each production
      @production_summaries = @productions.map do |production|
        build_advance_summary(production)
      end

      # Org-wide stats
      @total_unpaid = @production_summaries.sum { |s| s[:unpaid_amount] }
      @total_outstanding = @production_summaries.sum { |s| s[:outstanding_amount] }
      @total_issued_this_month = @production_summaries.sum { |s| s[:issued_this_month] }
      @unpaid_count = @production_summaries.sum { |s| s[:unpaid_count] }
      @outstanding_count = @production_summaries.sum { |s| s[:outstanding_count] }
      @repaid_count = @production_summaries.sum { |s| s[:repaid_count] }
    end

    def build_advance_summary(production)
      advances = production.person_advances
      all_outstanding = advances.outstanding
      unpaid = all_outstanding.unpaid
      outstanding = all_outstanding.paid
      repaid = advances.fully_recovered

      {
        production: production,
        unpaid_count: unpaid.count,
        unpaid_amount: unpaid.sum(:original_amount),
        outstanding_count: outstanding.count,
        outstanding_amount: outstanding.sum(:remaining_balance),
        repaid_count: repaid.count,
        issued_this_month: advances.where("issued_at >= ?", Date.current.beginning_of_month).sum(:original_amount)
      }
    end
  end
end
