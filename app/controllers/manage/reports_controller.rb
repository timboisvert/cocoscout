# frozen_string_literal: true

require "csv"

module Manage
  # Reporting hub for the Pro plan. Every report is scoped to the current
  # organization (through its productions/shows) and gated to the paid tier by
  # Manage::PaidFeatureGate (controller_path "manage/reports" => :reports).
  #
  # Every report action builds a uniform +@report+ hash and renders through the
  # shared "show" template, so all reports look consistent and can be downloaded
  # as CSV (Excel) or printed to PDF (window.print) with no per-report work.
  class ReportsController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    # Landing-page catalog. Each report links to a built page.
    REPORT_CATALOG = [
      {
        title: "Financials",
        icon: "chart-bar",
        reports: [
          { key: :revenue_by_production, title: "Revenue by Production", description: "Ticket and other revenue totaled per production." },
          { key: :revenue_over_time, title: "Revenue Over Time", description: "Monthly revenue across the last 12 months." },
          { key: :course_revenue, title: "Course Revenue & Fees", description: "Gross, platform fees, and net for every course." }
        ]
      },
      {
        title: "Payouts",
        icon: "dollar-sign",
        reports: [
          { key: :payouts_summary, title: "Payouts Summary", description: "What you've paid out and what's still owed." }
        ]
      },
      {
        title: "Programming",
        icon: "calendar",
        reports: [
          { key: :events_summary, title: "Events Summary", description: "Shows and events broken down by type and status." },
          { key: :cast_participation, title: "Cast Participation", description: "How many shows each performer and group is in." }
        ]
      }
    ].freeze

    # Route helper for each report key, for the hub cards.
    REPORT_PATH_HELPERS = {
      revenue_by_production: :manage_report_revenue_by_production_path,
      revenue_over_time: :manage_report_revenue_over_time_path,
      course_revenue: :manage_report_course_revenue_path,
      payouts_summary: :manage_report_payouts_summary_path,
      events_summary: :manage_report_events_summary_path,
      cast_participation: :manage_report_cast_participation_path
    }.freeze

    def index
      @report_catalog = REPORT_CATALOG
    end

    def revenue_by_production
      rows = organization.productions.active.schedulable.order(:name).map do |production|
        financials = show_financials_for(production_ids: [ production.id ])
        [
          production.name,
          financials.size,
          financials.sum { |f| f.ticket_count.to_i },
          financials.sum(&:total_revenue)
        ]
      end
      total_revenue = rows.sum { |r| r[3] }
      total_tickets = rows.sum { |r| r[2] }

      render_report(
        key: :revenue_by_production,
        title: "Revenue by Production",
        subtitle: "Ticket and other revenue totaled per production.",
        columns: [ col("Production"), col("Events", :number), col("Tickets", :number), col("Revenue", :currency) ],
        rows: rows,
        total_row: [ "Total", nil, total_tickets, total_revenue ]
      )
    end

    def revenue_over_time
      show_ids = Show.where(production_id: organization.productions.select(:id)).select(:id)
      financials = ShowFinancials.where(show_id: show_ids).includes(:show)
      by_month = Hash.new(0.0)
      12.downto(0) { |i| by_month[(Time.zone.today.beginning_of_month - i.months)] = 0.0 }

      financials.each do |f|
        date = f.show&.date_and_time
        next if date.nil?

        month = date.to_date.beginning_of_month
        by_month[month] += f.total_revenue if by_month.key?(month)
      end

      months = by_month.sort_by(&:first)
      rows = months.map { |month, amount| [ month.strftime("%b %Y"), amount ] }

      render_report(
        key: :revenue_over_time,
        title: "Revenue Over Time",
        subtitle: "Monthly revenue across the last 12 months.",
        columns: [ col("Month"), col("Revenue", :currency) ],
        rows: rows,
        total_row: [ "Total", months.sum { |_, amount| amount } ]
      )
    end

    def events_summary
      shows = Show.where(production_id: organization.productions.select(:id))
      by_type = shows.group(:event_type).count.sort_by { |_, count| -count }

      render_report(
        key: :events_summary,
        title: "Events Summary",
        subtitle: "Shows and events broken down by type and status.",
        stats: [
          { label: "Total events", value: shows.count },
          { label: "Upcoming", value: shows.where(canceled: false).where("date_and_time >= ?", Time.current).count },
          { label: "Past", value: shows.where(canceled: false).where("date_and_time < ?", Time.current).count },
          { label: "Canceled", value: shows.where(canceled: true).count }
        ],
        columns: [ col("Event type"), col("Count", :number) ],
        rows: by_type.map { |type, count| [ (type.presence || "Show").to_s.titleize, count ] },
        total_row: [ "Total", shows.count ]
      )
    end

    def cast_participation
      show_ids = Show.where(production_id: organization.productions.select(:id)).select(:id)
      assignments = ShowPersonRoleAssignment.where(show_id: show_ids).where.not(assignable_id: nil)

      grouped = assignments.group(:assignable_type, :assignable_id)
      counts = grouped.count
      shows_per = grouped.distinct.count(:show_id)

      people = Person.where(id: counts.keys.select { |type, _| type == "Person" }.map(&:last)).index_by(&:id)
      groups = Group.where(id: counts.keys.select { |type, _| type == "Group" }.map(&:last)).index_by(&:id)

      rows = counts.map do |(type, id), assignment_count|
        entity = type == "Person" ? people[id] : groups[id]
        next if entity.nil?

        [ entity.name, type, shows_per[[ type, id ]].to_i, assignment_count ]
      end.compact.sort_by { |r| -r[2] }

      render_report(
        key: :cast_participation,
        title: "Cast Participation",
        subtitle: "How many shows each performer and group is in.",
        columns: [ col("Name"), col("Type"), col("Shows", :number), col("Role assignments", :number) ],
        rows: rows
      )
    end

    def payouts_summary
      show_ids = Show.where(production_id: organization.productions.select(:id)).select(:id)
      payouts = ShowPayout.where(show_id: show_ids)

      amount_by_status = payouts.group(:status).sum(:total_payout)
      count_by_status = payouts.group(:status).count
      total_amount = payouts.sum(:total_payout)
      paid_amount = amount_by_status["paid"] || 0

      rows = amount_by_status.sort_by { |_, amount| -amount }.map do |status, amount|
        [ (status.presence || "unknown").to_s.titleize, count_by_status[status].to_i, amount ]
      end

      render_report(
        key: :payouts_summary,
        title: "Payouts Summary",
        subtitle: "What you've paid out and what's still owed.",
        stats: [
          { label: "Total", value: format_currency(total_amount) },
          { label: "Paid", value: format_currency(paid_amount) },
          { label: "Outstanding", value: format_currency(total_amount - paid_amount) }
        ],
        columns: [ col("Status"), col("Payouts", :number), col("Amount", :currency) ],
        rows: rows,
        total_row: [ "Total", payouts.count, total_amount ]
      )
    end

    def course_revenue
      offerings = CourseOffering.where(production_id: organization.productions.select(:id)).includes(:production)

      rows = offerings.map do |offering|
        confirmed = offering.course_registrations.where(status: "confirmed")
        gross = confirmed.sum(:amount_cents)
        fees = confirmed.sum(:cocoscout_fee_cents)
        next if confirmed.count.zero?

        [ offering.production.name, confirmed.count, gross / 100.0, fees / 100.0, (gross - fees) / 100.0 ]
      end.compact.sort_by { |r| -r[2] }

      render_report(
        key: :course_revenue,
        title: "Course Revenue & Fees",
        subtitle: "Gross, platform fees, and net for every course.",
        columns: [ col("Course"), col("Registrations", :number), col("Gross", :currency), col("Platform fees", :currency), col("Net", :currency) ],
        rows: rows,
        total_row: [ "Total", rows.sum { |r| r[1] }, rows.sum { |r| r[2] }, rows.sum { |r| r[3] }, rows.sum { |r| r[4] } ]
      )
    end

    private

    def organization
      Current.organization
    end

    # Column descriptor: label + value format (:text, :number, :currency).
    def col(label, format = :text)
      { label: label, format: format }
    end

    # Build the uniform report and respond as HTML (shared template) or CSV.
    def render_report(key:, title:, subtitle:, columns:, rows:, total_row: nil, stats: [])
      @report = {
        key: key,
        title: title,
        subtitle: subtitle,
        stats: stats,
        columns: columns,
        rows: rows,
        total_row: total_row,
        filename: key.to_s.dasherize,
        csv_path: send(REPORT_PATH_HELPERS.fetch(key), format: :csv)
      }

      respond_to do |format|
        format.html { render :show }
        format.csv { send_data report_to_csv(@report), filename: "#{@report[:filename]}-#{Date.current.iso8601}.csv", type: "text/csv" }
      end
    end

    def report_to_csv(report)
      CSV.generate do |csv|
        csv << report[:columns].map { |c| c[:label] }
        report[:rows].each do |row|
          csv << row.each_with_index.map { |value, i| csv_cell(value, report[:columns][i]) }
        end
        if report[:total_row]
          csv << report[:total_row].each_with_index.map { |value, i| csv_cell(value, report[:columns][i]) }
        end
      end
    end

    # Raw values for CSV (numbers stay numeric; currency as a plain number).
    def csv_cell(value, _column)
      value
    end

    def format_currency(amount)
      "$#{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', amount.to_f))}"
    end

    # ShowFinancials scoped to the org (optionally to specific productions).
    def show_financials_for(production_ids: nil)
      ids = production_ids || organization.productions.select(:id)
      show_ids = Show.where(production_id: ids).select(:id)
      ShowFinancials.where(show_id: show_ids).to_a
    end
  end
end
