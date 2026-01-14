# frozen_string_literal: true

module Manage
  class ShowPayoutsController < Manage::ManageController
    before_action :set_production
    before_action :set_show_payout, only: [
      :show, :update, :edit_financials, :update_financials,
      :calculate, :mark_paid,
      :mark_non_revenue, :unmark_non_revenue,
      :override, :save_override, :clear_override,
      :change_scheme, :apply_scheme_change,
      :mark_line_item_paid, :unmark_line_item_paid,
      :mark_all_offline, :send_payment_reminders
    ]

    def show
      @line_items = @show_payout.line_items.includes(:payee).by_amount
      @show_financials = @show.show_financials
    end

    def update
      if @show_payout.update(show_payout_params)
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def edit_financials
      @show_financials = @show.show_financials || @show.build_show_financials
    end

    def update_financials
      @show_financials = @show.show_financials || @show.create_show_financials
      attrs = show_financials_params.to_h

      # Convert indexed line items to arrays
      attrs = convert_line_items_to_arrays(attrs)

      @show_financials.assign_attributes(attrs)
      if @show_financials.save
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Financial data saved."
      else
        render :edit_financials, status: :unprocessable_entity
      end
    end

    def calculate
      # Ensure we have financials
      unless @show.show_financials&.complete?
        redirect_to manage_production_edit_money_show_financials_path(@production, @show),
                    alert: "Please enter financial data before calculating payouts."
        return
      end

      # Get the scheme to use (with any overrides)
      scheme = @show_payout.payout_scheme || @production.payout_schemes.find_by(is_default: true)
      rules = @show_payout.override_rules.presence || scheme&.rules

      unless rules.present?
        redirect_to manage_production_money_payout_schemes_path(@production),
                    alert: "Please create a payout scheme first."
        return
      end

      # Calculate payouts
      result = PayoutCalculator.calculate(
        show: @show,
        rules: rules
      )

      if result[:success]
        @show_payout.update!(
          calculated_at: Time.current,
          total_payout: result[:total]
        )

        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payouts calculated: #{helpers.number_to_currency(result[:total])} total."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not calculate payouts: #{result[:error]}"
      end
    end

    def approve
      if @show_payout.approve!(Current.user)
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout approved and locked."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not approve payout."
      end
    end

    def mark_paid
      if @show_payout.mark_paid!
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout marked as paid."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "Could not mark as paid."
      end
    end

    def mark_non_revenue
      financials = @show.show_financials || @show.create_show_financials!
      financials.update!(non_revenue_override: true)
      redirect_to manage_production_money_index_path(@production),
                  notice: "#{helpers.show_display_name(@show)} marked as non-revenue event."
    end

    def unmark_non_revenue
      if @show.show_financials&.non_revenue_override?
        @show.show_financials.update!(non_revenue_override: false)
        redirect_to manage_production_edit_money_show_financials_path(@production, @show),
                    notice: "Event restored as revenue event. Enter financial data below."
      else
        redirect_to manage_production_money_index_path(@production),
                    alert: "This event was not marked as non-revenue."
      end
    end

    def override
      @default_scheme = @production.payout_schemes.find_by(is_default: true)
      @current_rules = @show_payout.override_rules.presence || @default_scheme&.rules || {}

      if turbo_frame_request?
        render partial: "manage/show_payouts/override_modal"
      end
    end

    def save_override
      rules = build_override_rules
      @show_payout.update!(override_rules: rules)
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "Custom rules saved for this show."
    end

    def clear_override
      @show_payout.update!(override_rules: nil)
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "Custom rules cleared. Using default scheme."
    end

    def change_scheme
      @available_schemes = @production.payout_schemes.order(:name)
      @current_scheme = @show_payout.payout_scheme
      @future_shows_count = @production.shows
        .where("date_and_time > ?", @show.date_and_time)
        .where(id: ShowPayout.where(payout_scheme: @current_scheme).select(:show_id))
        .count
    end

    def apply_scheme_change
      new_scheme = @production.payout_schemes.find(params[:payout_scheme_id])
      apply_to_future = params[:apply_to_future] == "1"

      if apply_to_future
        # Find all shows on or after this one that currently use the same scheme
        current_scheme = @show_payout.payout_scheme
        shows_to_update = @production.shows
          .where("date_and_time >= ?", @show.date_and_time)
          .includes(:show_payout)
          .select { |s| s.show_payout&.payout_scheme_id == current_scheme&.id }

        updated_count = 0
        shows_to_update.each do |show|
          show.show_payout.update!(payout_scheme: new_scheme, override_rules: nil)
          updated_count += 1
        end

        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout scheme changed to \"#{new_scheme.name}\" for #{updated_count} show#{"s" if updated_count != 1}."
      else
        # Clear any custom overrides when changing scheme
        @show_payout.update!(payout_scheme: new_scheme, override_rules: nil)
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "Payout scheme changed to \"#{new_scheme.name}\" for this show."
      end
    end

    def mark_line_item_paid
      line_item = @show_payout.line_items.find(params[:line_item_id])
      method = params[:payment_method].presence
      notes = params[:payment_notes].presence
      line_item.mark_as_already_paid!(Current.user, method: method, notes: notes)

      respond_to do |format|
        format.html do
          redirect_to manage_production_money_show_payout_path(@production, @show),
                      notice: "#{line_item.payee_name} marked as paid#{method ? " via #{line_item.payment_method_label}" : ""}."
        end
        format.any { head :ok }
      end
    end

    def unmark_line_item_paid
      line_item = @show_payout.line_items.find(params[:line_item_id])
      line_item.unmark_as_already_paid!
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "#{line_item.payee_name} no longer marked as paid."
    end

    def mark_all_offline
      method = params[:payment_method].presence || "historical"
      notes = params[:payment_notes].presence

      count = 0
      @show_payout.line_items.not_already_paid.each do |line_item|
        line_item.mark_as_offline_paid!(Current.user, method: method, notes: notes)
        count += 1
      end

      if count > 0
        # Auto-mark payout as paid if all line items are now paid
        if @show_payout.line_items.all?(&:paid?)
          @show_payout.mark_paid!
        end
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "#{count} payment#{"s" if count != 1} marked as #{ShowPayoutLineItem::PAYMENT_METHODS.include?(method) ? method : "paid"}."
      else
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    alert: "No unpaid line items to mark."
      end
    end

    def send_payment_reminders
      # Find performers without Venmo set up who have unpaid line items
      line_items_needing_setup = @show_payout.line_items.not_already_paid.select do |li|
        li.payee.respond_to?(:needs_venmo_setup?) && li.payee.needs_venmo_setup?
      end

      if line_items_needing_setup.empty?
        redirect_to manage_production_money_show_payout_path(@production, @show),
                    notice: "All performers have Venmo set up!"
        return
      end

      # TODO: Implement actual email sending when mailer is set up
      count = line_items_needing_setup.size
      redirect_to manage_production_money_show_payout_path(@production, @show),
                  notice: "Payment setup reminders will be sent to #{count} performer#{"s" if count != 1}. (Coming soon!)"
    end

    private

    def set_production
      @production = Current.production
    end

    def set_show_payout
      # ShowPayout is keyed by show - find or create
      @show = @production.shows.find(params[:id])
      @show_payout = @show.show_payout || @show.create_show_payout!(
        payout_scheme: @production.payout_schemes.find_by(is_default: true),
        status: "draft"
      )
    end

    def show_payout_params
      params.require(:show_payout).permit(:notes, :payout_scheme_id)
    end

    def show_financials_params
      params.require(:show_financials).permit(
        :revenue_type, :ticket_count, :ticket_revenue, :flat_fee,
        :other_revenue, :expenses, :notes, :data_confirmed,
        other_revenue_details: [ :description, :amount ],
        expense_details: [ :description, :amount ]
      )
    end

    def override_rules_params
      params.require(:override_rules).permit!
    end

    def build_override_rules
      rules_params = params[:override_rules] || {}
      distribution_params = rules_params[:distribution] || {}
      method = distribution_params[:method] || "per_ticket_guaranteed"

      # Build distribution
      distribution = { "method" => method }

      case method
      when "per_ticket_guaranteed"
        distribution["per_ticket_rate"] = distribution_params[:per_ticket_rate]&.to_f || 1.0
        distribution["minimum"] = distribution_params[:minimum]&.to_f || 0
      when "flat_fee"
        distribution["flat_amount"] = distribution_params[:flat_amount]&.to_f || 0
      when "custom"
        # Custom per-person: use flat_fee method with all amounts in performer_overrides
        distribution = { "method" => "flat_fee", "flat_amount" => 0 }
      end

      # Build performer overrides
      performer_overrides = {}
      overrides_params = rules_params[:performer_overrides] || {}
      overrides_params.each do |person_id, override_data|
        next if person_id.blank?

        override = {}
        override["per_ticket_rate"] = override_data[:per_ticket_rate].to_f if override_data[:per_ticket_rate].present?
        override["minimum"] = override_data[:minimum].to_f if override_data[:minimum].present?
        override["flat_amount"] = override_data[:flat_amount].to_f if override_data[:flat_amount].present?

        performer_overrides[person_id.to_s] = override if override.any?
      end

      {
        "allocation" => [],
        "distribution" => distribution,
        "performer_overrides" => performer_overrides
      }
    end

    # Convert indexed hash params (from dynamic form) to arrays of hashes
    # e.g., { "0" => { "description" => "X", "amount" => "10" }, "1" => ... }
    # becomes [{ "description" => "X", "amount" => 10.0 }, ...]
    def convert_line_items_to_arrays(attrs)
      %w[other_revenue_details expense_details].each do |field|
        if attrs[field].is_a?(Hash) || attrs[field].is_a?(ActionController::Parameters)
          items = attrs[field].values.map do |item|
            next if item["description"].blank? && item["amount"].blank?
            { "description" => item["description"].to_s, "amount" => item["amount"].to_f }
          end.compact
          attrs[field] = items.presence
        elsif attrs[field].blank?
          # Keep nil/empty as is - don't overwrite with empty array
          attrs.delete(field)
        end
      end
      attrs
    end
  end
end
