# frozen_string_literal: true

module Manage
  class CourseOfferingPayoutsController < Manage::ManageController
    before_action :load_course_offering
    before_action :load_payout, except: [ :calculate ]

    def show
      # Keep the revenue summary current with registrations (safe: no line-item
      # changes) so a stale calculation doesn't show the wrong revenue/net.
      CoursePayoutCalculator.new(@course_offering).refresh_summary!
      @payout.reload

      @registrations = @course_offering.course_registrations
        .where.not(status: :cancelled)
        .includes(:person)
      @line_items = @payout.line_items.order(:created_at)
      @contract = @course_offering.contract
      @has_contract = @contract&.revenue_share? || @contract&.ticket_revenue_minus_fee?
      @coverage_type = @course_offering.feature_credit_redemption&.feature_credit&.coverage_type

      # Gross (before refunds) and the refunded portion, so the revenue summary
      # can show "$120 gross − $80 refunds = $40 kept" rather than just the net.
      @gross_cents = @course_offering.course_registrations.confirmed.sum(:amount_cents) +
        @course_offering.course_registrations.refunded.sum(:amount_cents)
      @refunds_cents = @course_offering.course_registrations.refunded.sum(:amount_cents)

      # Instructors we can guide the org to pay (Persons on the payout rail).
      @instructors = @course_offering.instructor_people.to_a
      @instructors = [ @course_offering.instructor_person ].compact if @instructors.empty?

      # Everyone who gets paid out of this course — the instructor/contract line
      # items plus the organization's own remainder — each with its run status.
      settlement = CoursePayoutSettlement.new(@payout)
      @org_keeps_cents = settlement.org_keeps_cents
      @payout_rows = settlement.rows.map { |row| row.merge(status: run_status(row[:source], row[:payee])) }
      @course_run = current_course_run
    end

    # Add this course's payouts (instructors + the org's remainder) to the org's
    # open course payout run. Payees who haven't connected a bank are left owed
    # and can be added to a later run once they're ready.
    def add_to_run
      result = CoursePayoutRunService.add_to_run!(@payout, added_by: Current.user)

      if result.added.positive?
        notice = "Added #{result.added} #{'payout'.pluralize(result.added)} to the course payout run."
        if result.skipped.positive?
          notice += " #{result.skipped} still can't be paid until a bank is connected."
        end
        redirect_to manage_course_offering_payout_path(@course_offering), notice: notice
      else
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Nothing could be added yet — payees need to connect a bank before they can be paid."
      end
    end

    # Record what the org is paying each instructor. These become "calculated"
    # payout line items (payee = the instructor Person) — money set aside, but not
    # yet in a payout run. They get paid the same way performers do: added to the
    # org's performer payout run later.
    def pay_instructors
      amounts = params[:instructor_amounts] || {}

      CourseOfferingPayout.transaction do
        amounts.each do |person_id, dollars|
          cents = (dollars.to_f * 100).round
          person = @course_offering.instructor_people.find_by(id: person_id) ||
            (@course_offering.instructor_person if @course_offering.instructor_person_id.to_s == person_id.to_s)
          next unless person

          line = @payout.line_items.find_by(payee: person)

          if cents <= 0
            line&.destroy! unless line&.paid?
            next
          end

          if line
            line.update!(amount_cents: cents) unless line.paid?
          else
            @payout.line_items.create!(
              payee: person,
              amount_cents: cents,
              label: person.name,
              calculation_details: { type: "instructor", person_id: person.id }
            )
          end
        end

        @payout.update!(
          total_payout_cents: @payout.line_items.sum(:amount_cents),
          status: "calculated"
        )
      end

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Instructor payments saved."
    end

    def calculate
      calculator = CoursePayoutCalculator.new(@course_offering)
      @payout = calculator.calculate!

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Payout set up successfully."
    end

    def recalculate
      unless @course_offering.contract&.revenue_share? || @course_offering.contract&.ticket_revenue_minus_fee?
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Recalculate is only available for contract-based payouts."
        return
      end

      unless @payout.can_recalculate?
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Cannot recalculate — payout has not been calculated yet."
        return
      end

      # Reset paid status so the payout can be re-evaluated
      if @payout.paid?
        @payout.update!(status: "calculated", paid_at: nil)
      end

      calculator = CoursePayoutCalculator.new(@course_offering)
      @payout = calculator.calculate!

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Payout recalculated successfully."
    end

    def add_line_item
      amount_cents = (params[:amount].to_f * 100).round

      if amount_cents <= 0
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Amount must be greater than zero."
        return
      end

      @payout.line_items.create!(
        amount_cents: amount_cents,
        label: params[:label].presence || "Payment",
        calculation_details: { type: "manual" }
      )

      @payout.update!(
        total_payout_cents: @payout.line_items.sum(:amount_cents),
        status: "calculated"
      )

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Payment added."
    end

    def remove_line_item
      line_item = @payout.line_items.find(params[:line_item_id])

      if line_item.paid?
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Cannot remove a line item that has already been marked as paid."
        return
      end

      line_item.destroy!

      @payout.update!(
        total_payout_cents: @payout.line_items.sum(:amount_cents)
      )

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Payment removed."
    end

    # Offline fallback: record that an instructor was paid another way (cash/check/
    # Zelle/etc.) when they can't be paid through a Stripe run. Settles the payout
    # once every line is paid, so the course leaves "awaiting payout".
    def mark_line_item_paid
      line_item = @payout.line_items.find(params[:line_item_id])
      method = params[:method].presence_in(ShowPayoutLineItem::MANUAL_PAYMENT_METHODS) || "other"
      line_item.mark_paid!(user: Current.user, method: method, notes: params[:notes].presence)

      if @payout.line_items.reload.all?(&:paid?) && !@payout.paid?
        @payout.update!(status: "paid", paid_at: Time.current)
      end

      redirect_to manage_course_offering_payout_path(@course_offering), notice: "Recorded as paid another way."
    rescue ActiveRecord::RecordNotFound
      redirect_to manage_course_offering_payout_path(@course_offering), alert: "That payout line wasn't found."
    end

    def update_revenue_override
      override = params[:total_revenue_override_cents]

      if override.present?
        # Convert dollar amount to cents
        override_cents = (override.to_f * 100).round
        @payout.update!(total_revenue_override_cents: override_cents)
      else
        @payout.update!(total_revenue_override_cents: nil)
      end

      # Recalculate with the override
      calculator = CoursePayoutCalculator.new(@course_offering)
      calculator.calculate!

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Revenue override updated and payout recalculated."
    end

    private

    def load_course_offering
      @course_offering = CourseOffering.find(params[:course_offering_id])
      unless @course_offering.production.organization == Current.organization
        redirect_to manage_course_offerings_path, alert: "Course offering not found."
        return
      end
      @production = @course_offering.production
      unless Current.user.accessible_productions.include?(@production)
        redirect_to manage_course_offerings_path, alert: "You do not have access to this course offering."
      end
    end

    def load_payout
      @payout = @course_offering.course_offering_payout
      return if @payout

      # No payout record yet — for the payout page itself, set one up on the fly so
      # there's always a page to manage (works with or without a contract, and is
      # safe to re-run). Other actions still need an existing payout.
      if action_name == "show"
        @payout = CoursePayoutCalculator.new(@course_offering).calculate!
      else
        redirect_to manage_course_offering_path(@course_offering),
          alert: "No payout has been calculated yet."
      end
    end

    # A payee's status in the course payout run: already paid, waiting in the run,
    # ready to add, or blocked because they haven't connected a bank.
    def run_status(source, payee)
      contribution = PayoutContribution.find_by(source: source)
      if contribution
        return :paid if contribution.payout_batch_item&.paid?

        return :in_run
      end

      return :needs_bank unless payee.respond_to?(:can_receive_payouts?) && payee.can_receive_payouts?

      :ready
    end

    def current_course_run
      PayoutBatch.of_kind("course").open_runs
        .where(organization: Current.organization).order(:created_at).first
    end
  end
end
