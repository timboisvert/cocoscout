# frozen_string_literal: true

module Manage
  class CourseOfferingPayoutsController < Manage::ManageController
    before_action :load_course_offering
    before_action :load_payout, except: [ :calculate ]

    def show
      @registrations = @course_offering.course_registrations
        .where.not(status: :cancelled)
        .includes(:person)
      @line_items = @payout.line_items.order(:created_at)
      @contract = @course_offering.contract
      @has_contract = @contract&.revenue_share?
    end

    def calculate
      calculator = CoursePayoutCalculator.new(@course_offering)
      @payout = calculator.calculate!

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "Payout set up successfully."
    end

    def recalculate
      unless @course_offering.contract&.revenue_share?
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Recalculate is only available for contract-based payouts."
        return
      end

      unless @payout.can_recalculate?
        redirect_to manage_course_offering_payout_path(@course_offering),
          alert: "Cannot recalculate — some line items have already been marked as paid."
        return
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

    def mark_line_item_paid
      line_item = @payout.line_items.find(params[:line_item_id])
      line_item.mark_paid!(
        user: Current.user,
        method: params[:payment_method],
        notes: params[:payment_notes]
      )

      if @payout.all_line_items_paid?
        @payout.mark_paid!
      end

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "#{line_item.payee_name} marked as paid."
    end

    def mark_all_paid
      method = params[:payment_method] || "other"

      @payout.line_items.unpaid.each do |line_item|
        line_item.mark_paid!(
          user: Current.user,
          method: method,
          notes: params[:payment_notes]
        )
      end

      @payout.mark_paid!

      redirect_to manage_course_offering_payout_path(@course_offering),
        notice: "All line items marked as paid."
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
      unless @payout
        redirect_to manage_course_offering_path(@course_offering),
          alert: "No payout has been calculated yet."
      end
    end
  end
end
