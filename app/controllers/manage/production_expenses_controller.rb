# frozen_string_literal: true

module Manage
  class ProductionExpensesController < Manage::ManageController
    before_action :set_production
    before_action :set_production_expense, only: [ :show, :edit, :update, :destroy, :recalculate, :override_allocation ]

    def index
      @production_expenses = @production.production_expenses.ordered
    end

    def show
      @allocations = @production_expense.allocations.ordered.includes(:show)
    end

    def new
      @production_expense = @production.production_expenses.build(
        spread_method: "fixed_months",
        spread_months: 3,
        exclude_non_revenue: true,
        exclude_canceled: true
      )
      @upcoming_shows = upcoming_shows_for_selection
    end

    def create
      @production_expense = @production.production_expenses.build(production_expense_params)

      if @production_expense.save
        @production_expense.recalculate_allocations!
        redirect_to manage_production_money_expense_path(@production, @production_expense),
                    notice: "Production expense created."
      else
        @upcoming_shows = upcoming_shows_for_selection
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @upcoming_shows = upcoming_shows_for_selection
    end

    def update
      if @production_expense.update(production_expense_params)
        @production_expense.recalculate_allocations!
        redirect_to manage_production_money_expense_path(@production, @production_expense),
                    notice: "Production expense updated."
      else
        @upcoming_shows = upcoming_shows_for_selection
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @production_expense.destroy
      redirect_to manage_production_money_expenses_path(@production),
                  notice: "Production expense deleted."
    end

    def recalculate
      @production_expense.recalculate_allocations!
      redirect_to manage_production_money_expense_path(@production, @production_expense),
                  notice: "Allocations recalculated."
    end

    def override_allocation
      allocation = @production_expense.allocations.find(params[:allocation_id])

      if params[:clear_override]
        allocation.clear_override!
        redirect_to manage_production_money_expense_path(@production, @production_expense),
                    notice: "Override cleared."
      else
        allocation.override!(
          params[:allocated_amount].to_f,
          reason: params[:override_reason]
        )
        redirect_to manage_production_money_expense_path(@production, @production_expense),
                    notice: "Allocation updated."
      end
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_production_expense
      @production_expense = @production.production_expenses.find(params[:id])
    end

    def production_expense_params
      params.require(:production_expense).permit(
        :name,
        :description,
        :category,
        :total_amount,
        :purchase_date,
        :spread_method,
        :spread_months,
        :spread_event_count,
        :spread_start_date,
        :spread_end_date,
        :exclude_non_revenue,
        :exclude_canceled,
        :active,
        selected_show_ids: [],
        event_type_filter: []
      )
    end

    def upcoming_shows_for_selection
      @production.shows
                 .where("date_and_time >= ?", Date.current)
                 .where(canceled: false)
                 .order(:date_and_time)
                 .limit(100)
    end
  end
end
