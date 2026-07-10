# frozen_string_literal: true

module Manage
  # Reporting hub for the Pro plan. Every report is scoped to the
  # current organization (through its productions/shows). Gated to the paid tier
  # by Manage::PaidFeatureGate (controller_path "manage/reports" => :reports).
  class ReportsController < Manage::ManageController
    before_action :ensure_org_owner_or_manager

    # Report catalog rendered on the landing page. `status: :available` reports
    # link to a built page; `:coming_soon` are on the roadmap.
    REPORT_CATALOG = [
      {
        title: "Financials",
        reports: [
          { key: :revenue_by_production, title: "Revenue by Production", description: "Ticket and other revenue totaled per production." },
          { key: :revenue_over_time, title: "Revenue Over Time", description: "Monthly revenue across the last 12 months." },
          { key: :payouts_summary, title: "Payouts Summary", description: "What you've paid out and what's still owed." },
          { key: :course_revenue, title: "Course Revenue & Fees", description: "Gross, platform fees, and net for every course." }
        ]
      },
      {
        title: "Programming",
        reports: [
          { key: :events_summary, title: "Events Summary", description: "Shows and events broken down by type and status." },
          { key: :cast_participation, title: "Cast Participation", description: "How many shows each performer and group is in." }
        ]
      },
      {
        title: "Coming soon",
        reports: [
          { key: :attendance, title: "Attendance", description: "Attendance across shows and events.", status: :coming_soon },
          { key: :availability_response, title: "Availability Response Rates", description: "How reliably your cast responds to availability.", status: :coming_soon },
          { key: :staffing_hours, title: "Staffing Hours", description: "Scheduled staff hours and labor totals.", status: :coming_soon }
        ]
      }
    ].freeze

    def index
      @report_catalog = REPORT_CATALOG
    end

    def revenue_by_production
      @rows = organization.productions.active.schedulable.order(:name).map do |production|
        financials = show_financials_for(production_ids: [ production.id ])
        {
          production: production,
          revenue: financials.sum(&:total_revenue),
          tickets: financials.sum { |f| f.ticket_count.to_i },
          events_with_financials: financials.size
        }
      end
      @total_revenue = @rows.sum { |r| r[:revenue] }
      @total_tickets = @rows.sum { |r| r[:tickets] }
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

      @months = by_month.sort_by(&:first)
      @total = @months.sum { |_, amount| amount }
      @peak = @months.map { |_, amount| amount }.max || 0.0
    end

    def events_summary
      shows = Show.where(production_id: organization.productions.select(:id))
      @by_type = shows.group(:event_type).count.sort_by { |_, count| -count }
      @total = shows.count
      @upcoming = shows.where(canceled: false).where("date_and_time >= ?", Time.current).count
      @past = shows.where(canceled: false).where("date_and_time < ?", Time.current).count
      @canceled = shows.where(canceled: true).count
    end

    def cast_participation
      show_ids = Show.where(production_id: organization.productions.select(:id)).select(:id)
      assignments = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .where.not(assignable_id: nil)

      grouped = assignments.group(:assignable_type, :assignable_id)
      counts = grouped.count                       # { [type, id] => assignments }
      shows_per = grouped.distinct.count(:show_id)  # { [type, id] => distinct shows }

      people = Person.where(id: counts.keys.select { |type, _| type == "Person" }.map(&:last)).index_by(&:id)
      groups = Group.where(id: counts.keys.select { |type, _| type == "Group" }.map(&:last)).index_by(&:id)

      @rows = counts.map do |(type, id), assignment_count|
        entity = type == "Person" ? people[id] : groups[id]
        next if entity.nil?

        { name: entity.name, type: type, assignments: assignment_count, shows: shows_per[[ type, id ]].to_i }
      end.compact.sort_by { |r| -r[:shows] }
    end

    def payouts_summary
      show_ids = Show.where(production_id: organization.productions.select(:id)).select(:id)
      payouts = ShowPayout.where(show_id: show_ids)

      @by_status = payouts.group(:status).count
      @amount_by_status = payouts.group(:status).sum(:total_payout)
      @total_amount = payouts.sum(:total_payout)
      @paid_amount = @amount_by_status["paid"] || 0
      @outstanding = @total_amount - @paid_amount
    end

    def course_revenue
      offerings = CourseOffering.where(production_id: organization.productions.select(:id)).includes(:production)

      @rows = offerings.map do |offering|
        confirmed = offering.course_registrations.where(status: "confirmed")
        gross = confirmed.sum(:amount_cents)
        fees = confirmed.sum(:cocoscout_fee_cents)
        {
          offering: offering,
          registrations: confirmed.count,
          gross_cents: gross,
          fee_cents: fees,
          net_cents: gross - fees
        }
      end.reject { |r| r[:registrations].zero? }.sort_by { |r| -r[:gross_cents] }

      @total_gross = @rows.sum { |r| r[:gross_cents] }
      @total_fees = @rows.sum { |r| r[:fee_cents] }
    end

    private

    def organization
      Current.organization
    end

    # ShowFinancials scoped to the org (optionally to specific productions).
    def show_financials_for(production_ids: nil)
      ids = production_ids || organization.productions.select(:id)
      show_ids = Show.where(production_id: ids).select(:id)
      ShowFinancials.where(show_id: show_ids).to_a
    end
  end
end
