# frozen_string_literal: true

module Manage
  class PayrollController < ManageController
    before_action :set_payroll_run, only: %i[show_run start_run cancel_run complete_run]
    before_action :set_line_item, only: %i[mark_line_item_paid unmark_line_item_paid]

    def index
      load_payroll
    end

    def settings
      @schedule = Current.organization.payroll_schedule || Current.organization.build_payroll_schedule
    end

    def update_settings
      @schedule = Current.organization.payroll_schedule || Current.organization.build_payroll_schedule
      if @schedule.update(schedule_params)
        redirect_to manage_money_payroll_path, notice: "Payroll settings saved."
      else
        render :settings, status: :unprocessable_entity
      end
    end

    def new_run
      @schedule = Current.organization.payroll_schedule

      if @schedule
        # Use current period from schedule
        period = @schedule.current_period
        @period_start = period[:start]
        @period_end = period[:end]
      else
        # Default to last 2 weeks
        @period_end = Date.current
        @period_start = @period_end - 13.days
      end

      @payroll_run = Current.organization.payroll_runs.build(
        period_start: @period_start,
        period_end: @period_end
      )

      # Preview what would be included across all productions
      @preview_items = preview_line_items(@period_start, @period_end)
    end

    def create_run
      @payroll_run = Current.organization.payroll_runs.build(run_params)
      @payroll_run.created_by = Current.user

      if @payroll_run.save
        # Build line items from show payout line items in the period
        @payroll_run.build_line_items!

        if @payroll_run.payroll_line_items.any?
          redirect_to manage_money_payroll_run_path(@payroll_run),
                      notice: "Payroll run created with #{@payroll_run.payroll_line_items.count} people."
        else
          @payroll_run.cancel!
          redirect_to manage_money_payroll_path,
                      alert: "No eligible payouts found in this period."
        end
      else
        @period_start = @payroll_run.period_start
        @period_end = @payroll_run.period_end
        @preview_items = preview_line_items(@period_start, @period_end) if @period_start && @period_end
        render :new_run, status: :unprocessable_entity
      end
    end

    def show_run
      @line_items = @payroll_run.payroll_line_items.includes(:person, show_payout_line_items: { show_payout: :show }).by_name
      @paid_count = @line_items.select(&:paid?).count
      @unpaid_count = @line_items.reject(&:paid?).count
    end

    def start_run
      if @payroll_run.start_processing!(Current.user)
        redirect_to manage_money_payroll_run_path(@payroll_run),
                    notice: "Payroll run started. Mark payments as you process them."
      else
        redirect_to manage_money_payroll_run_path(@payroll_run),
                    alert: "Could not start payroll run."
      end
    end

    def cancel_run
      if @payroll_run.cancel!
        redirect_to manage_money_payroll_path,
                    notice: "Payroll run cancelled. Line items are available for future runs."
      else
        redirect_to manage_money_payroll_run_path(@payroll_run),
                    alert: "Could not cancel payroll run."
      end
    end

    def complete_run
      if @payroll_run.complete!
        redirect_to manage_money_payroll_path,
                    notice: "Payroll run marked as complete."
      else
        redirect_to manage_money_payroll_run_path(@payroll_run),
                    alert: "Could not complete payroll run."
      end
    end

    def mark_line_item_paid
      method = params[:payment_method]
      notes = params[:notes]

      @line_item.mark_as_paid!(Current.user, method: method, notes: notes)

      respond_to do |format|
        format.html { redirect_back fallback_location: manage_money_payroll_run_path(@payroll_run) }
        format.turbo_stream
      end
    end

    def unmark_line_item_paid
      @line_item.unmark_as_paid!

      respond_to do |format|
        format.html { redirect_back fallback_location: manage_money_payroll_run_path(@payroll_run) }
        format.turbo_stream
      end
    end

    private

    def load_payroll
      @schedule = Current.organization.payroll_schedule

      # Calculate current period and preview items if schedule exists
      if @schedule
        @current_period = @schedule.current_period
        @preview_items = preview_line_items(@current_period[:start], @current_period[:end]) if @current_period
        @recent_periods = @schedule.recent_periods(count: 3, include_current: false)
      end

      # Pending payroll runs (manually created or in progress)
      @pending_runs = Current.organization.payroll_runs.pending.includes(:payroll_line_items).by_period

      # Completed runs for history
      @completed_runs = Current.organization.payroll_runs.completed.includes(:payroll_line_items).by_period.limit(10)

      # Stats across all in-house productions
      @unpaid_line_items_count = unpaid_show_line_items.count
      @unpaid_amount = unpaid_show_line_items.sum("show_payout_line_items.amount - COALESCE(show_payout_line_items.advance_deduction, 0)")

      # Get production breakdown for context
      @productions = Current.organization.productions.where.not(production_type: "third_party").order(:name)
    end

    def set_payroll_run
      @payroll_run = Current.organization.payroll_runs.find(params[:id])
    end

    def set_line_item
      @payroll_run = Current.organization.payroll_runs.find(params[:run_id])
      @line_item = @payroll_run.payroll_line_items.find(params[:id])
    end

    def run_params
      params.require(:payroll_run).permit(:period_start, :period_end, :notes)
    end

    def schedule_params
      params.require(:payroll_schedule).permit(:active, :period_type, :period_anchor, :semi_monthly_days, :payday_timing, :payday_offset_days)
    end

    def in_house_production_ids
      @in_house_production_ids ||= Current.organization.productions.where.not(production_type: "third_party").pluck(:id)
    end

    def unpaid_show_line_items
      ShowPayoutLineItem
        .joins(show_payout: :show)
        .where(shows: { production_id: in_house_production_ids })
        .where(manually_paid: false)
        .where(payout_reference_id: nil)
        .where(payroll_line_item_id: nil)
        .where(paid_independently: false)
    end

    def preview_line_items(period_start, period_end)
      ShowPayoutLineItem
        .joins(show_payout: :show)
        .where(shows: { production_id: in_house_production_ids })
        .where(shows: { date_and_time: period_start.beginning_of_day..period_end.end_of_day })
        .where(manually_paid: false)
        .where(payout_reference_id: nil)
        .where(payroll_line_item_id: nil)
        .where(paid_independently: false)
        .where(is_guest: false)
        .includes(:payee, show_payout: { show: :production })
        .group_by(&:payee)
        .transform_values do |items|
          {
            show_count: items.count,
            gross: items.sum(&:amount),
            deductions: items.sum(&:advance_deduction),
            net: items.sum { |i| i.amount - (i.advance_deduction || 0) },
            productions: items.map { |i| i.show_payout.show.production.name }.uniq
          }
        end
    end
  end
end
