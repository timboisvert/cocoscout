# frozen_string_literal: true

module Manage
  class ShowPayoutsController < Manage::ManageController
    before_action :set_production
    before_action :set_show_payout, only: [
      :show, :update, :edit_financials, :update_financials,
      :calculate, :mark_paid, :reopen, :add_to_payout_run, :remove_from_run,
      :mark_non_revenue, :unmark_non_revenue,
      :override, :save_override, :clear_override,
      :change_scheme, :apply_scheme_change,
      :mark_line_item_paid, :unmark_line_item_paid,
      :mark_all_offline, :send_payment_reminders,
      :close_as_non_paying,
      :add_line_item, :remove_line_item, :add_missing_cast,
      :issue_advances, :reset_calculation,
      :promote_guest
    ]

    def show
      @is_third_party = @production.third_party?
      @contract = resolved_contract
      # Contract payments already logged against this specific show (what we owe /
      # are owed for it) — a contract show is paid from these, not from casting.
      @show_contract_payments = @show.contract_payments.includes(contract: :contractor).order(:due_date).to_a

      if @is_third_party && @contract&.revenue_share?
        setup_contractor_payout
      elsif @show_contract_payments.any?
        setup_contract_payout
      else
        setup_performer_payout
      end
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
      # Third-party revenue-share settles through the contract (financials sync to
      # the contract payment automatically), so there's nothing to calculate here.
      if @production.third_party? && @production.contract&.revenue_share?
        @contract = @production.contract
        if @show.show_financials&.has_data?
          redirect_to manage_money_show_payout_path(@show),
                      notice: "This show settles through the contract — the contractor's share is on the contract's payments."
        else
          redirect_to manage_money_show_payout_path(@show),
                      alert: "Please enter financial data before calculating payouts."
        end
        return
      end

      # Ensure we have financials
      unless @show.show_financials&.complete?
        redirect_to manage_edit_money_show_financials_path(@show),
                    alert: "Please enter financial data before calculating payouts."
        return
      end

      # Get the scheme to use (with any overrides)
      # Look for production-level scheme first, then organization-level
      scheme = @show_payout.payout_scheme || PayoutScheme.default_for_show(@show)
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

    # Add this show's calculated performer payouts to the org's open performer
    # payout run (one item per payee, a contribution per show).
    def add_to_payout_run
      result = PerformerPayoutRunService.add_show_payout!(@show_payout, added_by: Current.user)
      if result.added.positive?
        # Stay on the payout page — you can keep working here and pay from the run
        # whenever you're ready (the page shows a "View runs" link once added).
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Added #{helpers.pluralize(result.added, 'performer payout')} to your open performer payout run."
      else
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Nothing to add — these payouts are already in a run, or the performers can't be paid through Stripe yet."
      end
    end

    # Pull a payee back out of the open performer payout run for this show. Their
    # earning stays on the ledger (they're still owed) — this only cancels the
    # pending transfer, so they can be re-added anytime. Grouped by payee so a
    # multi-allocation payee comes out together. Destroying each PayoutContribution
    # re-settles or drops the batch item and re-totals the run (see the model);
    # already-paid items are skipped so settled money is never disturbed.
    def remove_from_run
      line_item = @show_payout.line_items.find(params[:line_item_id])
      line_ids = @show_payout.line_items
                             .where(payee_type: line_item.payee_type, payee_id: line_item.payee_id)
                             .ids
      contributions = PayoutContribution
                        .where(source_type: "ShowPayoutLineItem", source_id: line_ids)
                        .includes(:payout_batch_item)
                        .reject { |c| c.payout_batch_item&.paid? }

      if contributions.any?
        contributions.each(&:destroy)
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Removed #{line_item.payee_name} from the payout run. They're still owed — add them back anytime."
      else
        redirect_to manage_money_show_payout_path(@show),
                    alert: "#{line_item.payee_name} isn't in an open payout run."
      end
    end

    # Promote a guest performer to a real Person so they can connect a bank and be
    # paid through a payout run (replacing the old Venmo/Zelle guest flow).
    def promote_guest
      line_item = @show_payout.line_items.find(params[:line_item_id])
      result = GuestPromotionService.promote!(line_item: line_item, email: params[:email])
      if result.person
        redirect_to manage_money_show_payout_path(@show),
                    notice: "#{result.person.name} is set up as a payee — send them the bank setup link, then add them to a payout run."
      else
        redirect_to manage_money_show_payout_path(@show), alert: result.error
      end
    end

    # Reset calculation - undo a calculation, delete line items, clear calculated_at
    def reset_calculation
      # Don't allow resetting if any line items are paid
      if @show_payout.line_items.where(manually_paid: true).any?
        redirect_to manage_money_show_payout_path(@show),
                    alert: "Cannot reset calculation because some line items have been marked as paid."
        return
      end

      # Delete all line items and reset calculated_at
      @show_payout.transaction do
        @show_payout.line_items.destroy_all
        @show_payout.update!(calculated_at: nil, total_payout: nil, status: "awaiting_payout")
      end

      redirect_to manage_money_show_payout_path(@show),
                  notice: "Calculation reset. You can now issue advances or recalculate when ready."
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
                  notice: "#{@show.date_and_time.strftime('%b %-d')} - #{@show.display_name} marked as non-revenue event."
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
      @default_scheme = PayoutScheme.default_for_show(@show)
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
      # Support comma-separated IDs for grouped payees
      line_item_ids = params[:line_item_id].to_s.split(",").map(&:to_i)
      line_items = @show_payout.line_items.where(id: line_item_ids)

      method = params[:payment_method].presence
      notes = params[:payment_notes].presence

      line_items.each do |line_item|
        line_item.mark_as_already_paid!(Current.user, method: method, notes: notes)
      end

      # Explicit check in case the callback didn't fire (e.g., manually_paid was already true)
      @show_payout.reload
      if !@show_payout.paid? && @show_payout.line_items.all?(&:paid?)
        @show_payout.mark_paid!
      else
        # Even if the payout was already marked paid, still attempt contract settlement
        # in case it was missed (e.g. payout pre-dated this feature)
        @show_payout.settle_contract_payment!(payment_method: method, notes: notes) if @show_payout.paid?
      end

      first_item = line_items.first

      respond_to do |format|
        format.html do
          redirect_to manage_money_show_payout_path(@show),
                      notice: "#{first_item&.payee_name} marked as paid#{method ? " via #{first_item&.payment_method_label}" : ""}."
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
        # Skip auto-pay (bank-connected) performers — they're paid by the standard
        # payout run, never hand-marked here.
        next if line_item.auto_payout?

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
      # Find performers who haven't connected a bank yet and have unpaid line items
      line_items_needing_setup = @show_payout.line_items.not_already_paid.select do |li|
        li.payee.respond_to?(:can_receive_payouts?) && !li.payee.can_receive_payouts?
      end

      if line_items_needing_setup.empty?
        redirect_to manage_money_show_payout_path(@show),
                    notice: "Everyone has connected a bank!"
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
                  notice: "#{@show.date_and_time.strftime('%b %-d')} - #{@show.display_name} closed as non-paying."
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
      scheme = @show_payout.payout_scheme || PayoutScheme.default_for_show(@show)
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


    # Issue advances to cast members for this show
    def issue_advances
      advances_params = params[:advances] || {}
      default_amount = params[:default_amount].to_f

      created_count = 0
      skipped_count = 0
      total_issued = 0

      advances_params.each do |_key, advance_data|
        person_id = advance_data[:person_id]
        next if person_id.blank?

        # Skip if explicitly excluded
        if advance_data[:excluded] == "1" || advance_data[:excluded] == true
          skipped_count += 1
          next
        end

        amount = advance_data[:amount].present? ? advance_data[:amount].to_f : default_amount
        next if amount <= 0

        person = Person.find_by(id: person_id)
        next unless person

        # Issue the advance into the open performer run (paid to their bank when
        # the run funds; nets against their earnings on the ledger).
        result = AdvancePayoutService.issue!(
          person: person, amount_cents: (amount.to_d * 100).round,
          production: @production, issued_by: Current.user, show: @show
        )
        next unless result.advance

        created_count += 1
        total_issued += amount
      end

      if created_count > 0
        notice = "Added #{created_count} advance#{'s' if created_count != 1} (#{helpers.number_to_currency(total_issued)}) to your open performer run."
        notice += " Skipped #{skipped_count}." if skipped_count > 0
      else
        notice = "No advances issued."
        notice += " #{skipped_count} excluded or already have advances." if skipped_count > 0
      end

      redirect_to manage_money_show_payout_path(@show), notice: notice
    end

    private

    # A contract show whose money is a set of logged contract payments. Show what
    # we owe (outgoing → payable via the payout run) and what's owed to us
    # (incoming → expected income), instead of the casting calculation.
    def setup_contract_payout
      @contract_payout = true
      @outgoing_payments = @show_contract_payments.select(&:direction_outgoing?)
      @incoming_payments = @show_contract_payments.select(&:direction_incoming?)
    end

    # A show's contract, resolved however it's linked: through a booked space
    # rental, its production, or the contract payments already logged against it
    # (so a show that only carries linked payments is still recognized).
    def resolved_contract
      @show.space_rental&.contract || @production.contract ||
        @show.contract_payments.first&.contract
    end

    def setup_performer_payout
      @line_items = @show_payout.line_items.by_amount
      @show_financials = @show.show_financials

      # Load advances related to this show's performers
      person_ids = @line_items.where(payee_type: "Person").pluck(:payee_id).compact

      @show_advances = @production.person_advances.for_show(@show).outstanding.where(person_id: person_ids).includes(:person)
      @general_advances = @production.person_advances.general.outstanding.where(person_id: person_ids).includes(:person)

      @advances_by_person = {}
      (@show_advances + @general_advances).each do |advance|
        @advances_by_person[advance.person_id] ||= []
        @advances_by_person[advance.person_id] << advance
      end
    end

    # Third-party revenue-share shows are settled through the Contracts system now
    # (the contractor's cut becomes a ContractPayment that rides the Stripe payout
    # run), so this screen only DISPLAYS the split for the show — no line item, no
    # Venmo/Zelle. Payment happens on the contract.
    def setup_contractor_payout
      @show_financials = @show.show_financials
      @contractor = @contract.contractor
      @contractor_share_summary = @contract.revenue_share_summary
    end

    def set_production
      @production = @show&.production
    end

    def set_show_payout
      # ShowPayout is keyed by show - find or create
      @show = Show.joins(:production)
                  .where(productions: { organization: Current.organization })
                  .find(params[:id])
      @production = @show.production

      # Find default scheme for this show's date
      default_scheme = PayoutScheme.default_for_show(@show)

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
