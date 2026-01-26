# frozen_string_literal: true

module Manage
  class ShowPayoutsController < Manage::ManageController
    before_action :set_production
    before_action :set_show_payout, only: [
      :show, :update, :edit_financials, :update_financials,
      :calculate, :mark_paid, :reopen,
      :mark_non_revenue, :unmark_non_revenue,
      :override, :save_override, :clear_override,
      :change_scheme, :apply_scheme_change,
      :mark_line_item_paid, :unmark_line_item_paid,
      :mark_all_offline, :send_payment_reminders,
      :close_as_non_paying,
      :add_line_item, :remove_line_item, :add_missing_cast,
      :update_guest_payments
    ]

    def show
      @line_items = @show_payout.line_items.includes(:payee).by_amount
      @show_financials = @show.show_financials
    end

    def update
      if @show_payout.update(show_payout_params)
        redirect_to manage_money_show_payout_path(@show),
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
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Financial data saved."
      else
        render :edit_financials, status: :unprocessable_entity
      end
    end

    def calculate
      # Ensure we have financials
      unless @show.show_financials&.complete?
        redirect_to manage_edit_money_show_financials_path(@show),
                    alert: "Please enter financial data before calculating payouts."
        return
      end

      # Get the scheme to use (with any overrides)
      # Look for production-level scheme first, then organization-level
      scheme = @show_payout.payout_scheme ||
               @production.payout_schemes.find_by(is_default: true) ||
               Current.organization.payout_schemes.organization_level.find_by(is_default: true)
      rules = @show_payout.override_rules.presence || scheme&.rules

      unless rules.present?
        redirect_to manage_money_payout_schemes_path,
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

        redirect_to manage_money_show_payout_path(@show),
                    notice: "Payouts calculated: #{helpers.number_to_currency(result[:total])} total."
      else
        # Provide more helpful error messages
        error_message = result[:error]
        if error_message&.include?("No performers")
          redirect_to manage_money_show_payout_path(@show),
                      alert: "No performers are assigned to this show. Add cast members first, or use 'Close as Non-Paying' to close this show without payouts."
        else
          redirect_to manage_money_show_payout_path(@show),
                      alert: "Could not calculate payouts: #{error_message}"
        end
      end
    end

    def approve
      if @show_payout.approve!(Current.user)
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Payout approved and locked."
      else
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Could not approve payout."
      end
    end

    def mark_paid
      if @show_payout.mark_paid!
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Payout marked as paid."
      else
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Could not mark as paid."
      end
    end

    def mark_non_revenue
      financials = @show.show_financials || @show.create_show_financials!
      financials.update!(non_revenue_override: true)
      redirect_to manage_money_index_path,
                  notice: "#{view_context.show_display_name(@show)} marked as non-revenue event."
    end

    def unmark_non_revenue
      if @show.show_financials&.non_revenue_override?
        @show.show_financials.update!(non_revenue_override: false)
        redirect_to manage_edit_money_show_financials_path(@show),
                    notice: "Event restored as revenue event. Enter financial data below."
      else
        redirect_to manage_money_index_path,
                    alert: "This event was not marked as non-revenue."
      end
    end

    def override
      @default_scheme = @production.payout_schemes.find_by(is_default: true) ||
                        Current.organization.payout_schemes.organization_level.find_by(is_default: true)
      @current_rules = @show_payout.override_rules.presence || @default_scheme&.rules || {}

      if turbo_frame_request?
        render partial: "manage/show_payouts/override_modal"
      else
        # Redirect back to show page - modal-only feature
        redirect_to manage_money_show_payout_path(@show)
      end
    end

    def save_override
      rules = build_override_rules
      @show_payout.update!(override_rules: rules)
      redirect_to manage_money_show_payout_path(@show),
                  notice: "Custom rules saved for this show."
    end

    def clear_override
      @show_payout.update!(override_rules: nil)
      redirect_to manage_money_show_payout_path(@show),
                  notice: "Custom rules cleared. Using default scheme."
    end

    def change_scheme
      # Include both production-level and organization-level schemes
      @available_schemes = PayoutScheme.where(organization: Current.organization)
                                       .order(:name)
      @current_scheme = @show_payout.payout_scheme
      @future_shows_count = @production.shows
        .where("date_and_time > ?", @show.date_and_time)
        .where(id: ShowPayout.where(payout_scheme: @current_scheme).select(:show_id))
        .count
    end

    def apply_scheme_change
      # Find scheme from organization (includes both org-level and production-level)
      new_scheme = PayoutScheme.where(organization: Current.organization)
                               .find(params[:payout_scheme_id])
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

        redirect_to manage_money_show_payout_path(@show),
                    notice: "Payout scheme changed to \"#{new_scheme.name}\" for #{updated_count} show#{"s" if updated_count != 1}."
      else
        # Clear any custom overrides when changing scheme
        @show_payout.update!(payout_scheme: new_scheme, override_rules: nil)
        redirect_to manage_money_show_payout_path(@show),
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
          redirect_to manage_money_show_payout_path(@show),
                      notice: "#{line_item.payee_name} marked as paid#{method ? " via #{line_item.payment_method_label}" : ""}."
        end
        format.any { head :ok }
      end
    end

    def unmark_line_item_paid
      line_item = @show_payout.line_items.find(params[:line_item_id])
      line_item.unmark_as_already_paid!
      redirect_to manage_money_show_payout_path(@show),
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
        redirect_to manage_money_show_payout_path(@show),
                    notice: "#{count} payment#{"s" if count != 1} marked as #{ShowPayoutLineItem::PAYMENT_METHODS.include?(method) ? method : "paid"}."
      else
        redirect_to manage_money_show_payout_path(@show),
                    alert: "No unpaid line items to mark."
      end
    end

    def send_payment_reminders
      # Find performers without Venmo set up who have unpaid line items
      line_items_needing_setup = @show_payout.line_items.not_already_paid.select do |li|
        li.payee.respond_to?(:needs_venmo_setup?) && li.payee.needs_venmo_setup?
      end

      if line_items_needing_setup.empty?
        redirect_to manage_money_show_payout_path(@show),
                    notice: "All performers have Venmo set up!"
        return
      end

      # TODO: Implement actual email sending when mailer is set up
      count = line_items_needing_setup.size
      redirect_to manage_money_show_payout_path(@show),
                  notice: "Payment setup reminders will be sent to #{count} performer#{"s" if count != 1}. (Coming soon!)"
    end

    def close_as_non_paying
      # Clear any existing line items
      @show_payout.line_items.destroy_all

      # Mark as calculated with $0 total and paid
      @show_payout.update!(
        calculated_at: Time.current,
        total_payout: 0,
        status: "paid",
        override_rules: { "distribution" => { "method" => "no_pay" }, "closed_as_non_paying" => true }
      )

      redirect_to manage_money_index_path,
                  notice: "#{view_context.show_display_name(@show)} closed as non-paying."
    end

    # Reopen a paid payout to add more people or make changes
    def reopen
      unless @show_payout.paid?
        redirect_to manage_money_show_payout_path(@show),
                    alert: "This payout is not marked as paid."
        return
      end

      @show_payout.update!(status: "awaiting_payout")
      redirect_to manage_money_show_payout_path(@show),
                  notice: "Payout reopened. You can now add people or make changes."
    end

    # Add a line item for a specific person (manual addition)
    def add_line_item
      payee_type = params[:payee_type] || "Person"
      payee_id = params[:payee_id]
      amount = params[:amount].to_f

      unless payee_id.present?
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Please select a person to add."
        return
      end

      payee = payee_type == "Group" ? Group.find(payee_id) : Person.find(payee_id)

      # Check if already in payout
      if @show_payout.line_items.exists?(payee: payee)
        redirect_to manage_money_show_payout_path(@show),
                    alert: "#{payee.name} is already in this payout."
        return
      end

      # If payout was paid, reopen it
      was_paid = @show_payout.paid?
      @show_payout.update!(status: "awaiting_payout") if was_paid

      # Create the line item
      @show_payout.line_items.create!(
        payee: payee,
        amount: amount,
        calculation_details: {
          formula: "Manual addition",
          inputs: { manual: true },
          breakdown: [ "Manually added: #{helpers.number_to_currency(amount)}" ]
        }
      )

      @show_payout.recalculate_total!

      notice = "Added #{payee.name} with payout of #{helpers.number_to_currency(amount)}."
      notice += " Payout reopened." if was_paid

      redirect_to manage_money_show_payout_path(@show), notice: notice
    end

    # Remove a line item
    def remove_line_item
      line_item = @show_payout.line_items.find(params[:line_item_id])
      name = line_item.payee_name

      if line_item.paid?
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Cannot remove #{name} - they have already been paid. Unmark as paid first."
        return
      end

      line_item.destroy!
      @show_payout.recalculate_total!

      redirect_to manage_money_show_payout_path(@show),
                  notice: "Removed #{name} from payout."
    end

    # Add any cast members who are in the show but not yet in the payout
    def add_missing_cast
      # Get current cast from assignments
      assignments = @show.show_person_role_assignments.includes(:assignable)
      current_cast = assignments.map(&:assignable).compact.uniq.select { |p| p.is_a?(Person) }

      # Get people already in payout
      existing_payees = @show_payout.line_items.where(payee_type: "Person").pluck(:payee_id)

      # Find missing people
      missing = current_cast.reject { |p| existing_payees.include?(p.id) }

      if missing.empty?
        redirect_to manage_money_show_payout_path(@show),
                    notice: "All cast members are already in the payout."
        return
      end

      # Determine amount to pay - use the rules if available, otherwise $0
      scheme = @show_payout.payout_scheme ||
               @production.payout_schemes.find_by(is_default: true) ||
               Current.organization.payout_schemes.organization_level.find_by(is_default: true)
      rules = @show_payout.override_rules.presence || scheme&.rules
      amount = params[:amount]&.to_f || 0

      # If payout was paid, reopen it
      was_paid = @show_payout.paid?
      @show_payout.update!(status: "awaiting_payout") if was_paid

      # Add line items for missing cast
      missing.each do |person|
        @show_payout.line_items.create!(
          payee: person,
          amount: amount,
          calculation_details: {
            formula: "Added missing cast",
            inputs: { manual: true, added_after_calculation: true },
            breakdown: [ "Added as missing cast: #{helpers.number_to_currency(amount)}" ]
          }
        )
      end

      @show_payout.recalculate_total!

      notice = "Added #{missing.count} missing cast member#{'s' if missing.count != 1}."
      notice += " Payout reopened." if was_paid

      redirect_to manage_money_show_payout_path(@show), notice: notice
    end

    # Update payment info for guest performers
    def update_guest_payments
      guests_params = params[:guests] || {}
      updated_count = 0

      guests_params.each do |_key, guest_data|
        line_item = @show_payout.line_items.find_by(id: guest_data[:id], is_guest: true)
        next unless line_item

        # Normalize Venmo handle (remove @ prefix if present)
        venmo = guest_data[:venmo]&.strip
        venmo = venmo[1..] if venmo&.start_with?("@")

        line_item.update!(
          guest_venmo: venmo.presence,
          guest_zelle: guest_data[:zelle]&.strip.presence
        )
        updated_count += 1
      end

      redirect_to manage_money_show_payout_path(@show),
                  notice: "Updated payment info for #{updated_count} guest#{'s' if updated_count != 1}."
    end

    private

    def set_production
      @production = @show&.production
    end

    def set_show_payout
      # ShowPayout is keyed by show - find or create
      @show = Show.joins(:production)
                  .where(productions: { organization: Current.organization })
                  .find(params[:id])
      @production = @show.production

      # Find default scheme: production-level first, then organization-level
      default_scheme = @production.payout_schemes.find_by(is_default: true) ||
                       Current.organization.payout_schemes.organization_level.find_by(is_default: true)

      @show_payout = @show.show_payout || @show.create_show_payout!(
        payout_scheme: default_scheme,
        status: "awaiting_payout"
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
      params.require(:override_rules).permit(
        distribution: [ :method, :per_ticket_rate, :minimum, :flat_amount ],
        performer_overrides: {}
      )
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
