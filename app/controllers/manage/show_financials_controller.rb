# frozen_string_literal: true

module Manage
  class ShowFinancialsController < Manage::ManageController
    before_action :set_show
    before_action :set_production
    before_action :set_show_financials

    # The show's money as a record to read (Tim, 2026-11-04): the card its
    # day shows on Settle up, and what was left after everything. Nothing is
    # entered here; that happens on the day.
    def show
      @show_payout = @show.show_payout
      @date = SettlementDay.day_for(Current.organization, @show.date_and_time)
      @day = SettleUp.day(Current.organization, @date)
      @piece = @day.shows.find { |piece| piece.show.id == @show.id } || SettleUp.show_piece(Current.organization, @show)
      @in_settle_up = SettleUp.in_settle_up?(Current.organization, @show)

      # Load production expense allocations for this show
      @production_expense_allocations = @show.production_expense_allocations
                                             .includes(:production_expense)
                                             .order("production_expenses.name")
    end

    def update
      handle_cleared_sections

      attrs = show_financials_params
      # A hand edit from the day's page darkens the show's confirm mark (Tim,
      # 2026-11-04): the money changed, so it's confirmed again on purpose,
      # and its payout is worked out again then. The worksheet's own
      # checkbox still says what it says.
      # The day's tickets modal says which kind of money the show took:
      # tickets, a flat fee, or none. None keeps what was typed and counts it
      # for nothing (SettleUp.show_piece), so a slip is undone by choosing again.
      if params[:revenue_choice].present?
        none = params[:revenue_choice] == "none"
        attrs[:revenue_type] = params[:revenue_choice] == "flat_fee" ? "flat_fee" : "ticket_sales"
        attrs[:non_revenue_override] = none
        attrs = attrs.except(:ticket_sales_lines_attributes, :flat_fee, :contractor_collected) if none
      end
      from_day = params[:return_to].to_s.start_with?("/manage/money/settle-up/")
      # A note alone changes no money, so it leaves the mark as it is.
      money_edit = (attrs.keys.map(&:to_s) - %w[notes]).any?
      attrs[:data_confirmed] = false if from_day && money_edit && !attrs.key?(:data_confirmed)
      if @show_financials.update(attrs)
        # Push the new numbers at this show's contract settlement. The service
        # decides whether there is one — asking @production.contract here got
        # the newest of a production's contracts rather than the one that booked
        # this show, and skipped minus-fee deals entirely.
        ContractPaymentSyncService.new(@show).call

        # The worksheet opened on the payout page returns there.
        back = if params[:return_to] == manage_money_show_payout_path(@show) || params[:return_to].to_s.start_with?("/manage/money/settle-up/")
          params[:return_to]
        else
          manage_money_show_financials_path(@show)
        end
        respond_to do |format|
          format.html { redirect_to back, notice: "Saved." }
          format.turbo_stream { redirect_to back, notice: "Saved." }
        end
      elsif params[:return_to].to_s.start_with?("/manage/money/settle-up/")
        redirect_to params[:return_to], alert: "That did not save: #{@show_financials.errors.full_messages.to_sentence}"
      else
        redirect_to SettleUp.money_entry_path(Current.organization, @show), alert: "That did not save: #{@show_financials.errors.full_messages.to_sentence}"
      end
    end

    def mark_non_revenue
      @show_financials.update!(non_revenue_override: true, data_confirmed: true)
      redirect_to manage_money_show_financials_path(@show),
                  notice: "#{@show.display_name} marked as non-revenue event."
    end

    def unmark_non_revenue
      @show_financials.update!(non_revenue_override: false)
      redirect_to manage_money_show_financials_path(@show),
                  notice: "#{@show.display_name} restored as revenue event."
    end

    private

    def set_show
      @show = Show.joins(:production)
                  .where(productions: { organization: Current.organization })
                  .find(params[:id])
    end

    def set_production
      @production = @show.production
    end

    def set_show_financials
      @show_financials = @show.show_financials&.tap { |sf| sf.expense_items.load } || @show.build_show_financials
      @show_financials.save! if @show_financials.new_record?
      @show_financials.ticket_sales_lines.load
      # The sources the worksheet's per-line picker offers. Archived ones are
      # left out of the picker but keep labelling the lines already using them.
      @ticket_sources = Current.organization.ticket_sources.hand_made.active.ordered.to_a
    end

    def require_manage_permission
      authorize_production_action!(:manage)
    end

    def handle_cleared_sections
      sf_params = params[:show_financials] || {}

      if sf_params[:other_revenue_details_cleared] == "1"
        @show_financials.other_revenue_details = []
        @show_financials.other_revenue = nil
      end

      if sf_params[:expense_items_cleared] == "1"
        # Clear the legacy expense_details JSONB; AR records are handled by _destroy in the nested attributes
        @show_financials.expense_details = []
        @show_financials.expenses = nil
      end
    end

    def show_financials_params
      permitted = params.require(:show_financials).permit(
        :revenue_type,
        :ticket_count,
        :ticket_revenue,
        :flat_fee,
        :other_revenue,
        :contractor_collected,
        :expenses,
        :notes,
        :data_confirmed,
        other_revenue_details: [ :description, :amount, :_destroy ],
        expense_details: [ :category, :description, :amount ],
        expense_items_attributes: [ :id, :category, :description, :amount, :position, :receipt, :_destroy ],
        ticket_sales_lines_attributes: [ :id, :ticket_source_id, :tickets_sold, :amount, :position, :_destroy ]
      )

      # A blank box is a zero (30 comps, no money, is a real row). A saved
      # ticket-source row cleared to nothing goes — the grid shows every
      # source, so "blank" means "sold nothing", not "leave the old numbers".
      if permitted[:ticket_sales_lines_attributes].present?
        permitted[:ticket_sales_lines_attributes].each_value do |line|
          line[:tickets_sold] = "0" if line.key?(:tickets_sold) && line[:tickets_sold].blank?
          line[:amount] = "0" if line.key?(:amount) && line[:amount].blank?
          next if line[:id].blank?

          line[:_destroy] = "1" if line[:tickets_sold].to_i.zero? && line[:amount].to_f.zero?
        end
      end

      # The day's worksheet sends a row per expense: a new one left blank is
      # nothing, a saved one blanked out goes.
      if permitted[:expense_items_attributes].present?
        permitted[:expense_items_attributes].each_value do |row|
          next if row[:amount].present?

          row[:_destroy] = "1" if row[:id].present?
        end
      end

      # Convert hash-style params to arrays for details fields
      # Rails sends {"0" => {desc: x}, "1" => {desc: y}} but we need [{desc: x}, {desc: y}]
      # Note: permitted params are ActionController::Parameters objects, need deep conversion
      if permitted[:expense_details].present?
        permitted[:expense_details] = permitted[:expense_details].to_unsafe_h.values.map do |v|
          v.is_a?(ActionController::Parameters) ? v.to_unsafe_h : v
        end
      end
      if permitted[:other_revenue_details].present?
        # Plain hashes, built once: reading the key back after assigning it
        # would hand back unpermitted Parameters. A blank line, or one
        # removed on the day's worksheet, is not a row.
        rows = permitted[:other_revenue_details].to_unsafe_h.values.map { |v| v.to_h.except("_destroy", "_removed") }
        rows = permitted[:other_revenue_details].to_unsafe_h.values.zip(rows).filter_map { |raw, row| row unless raw["_destroy"] == "1" || (row["description"].blank? && row["amount"].blank?) }
        permitted[:other_revenue_details] = rows
      end

      permitted
    end
  end
end
