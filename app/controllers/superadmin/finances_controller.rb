# frozen_string_literal: true

# Superadmin Finances: CocoScout's own money, every organization's money,
# the bills CocoScout sends, and the daily check against Stripe. Four pages
# and an org page:
#
#   /superadmin/finances                CocoScout: earned, spent, net, who paid
#   /superadmin/finances/organizations  each org: held, in flight, billed, paid us
#   /superadmin/finances/subscriptions  plans, comps, bills, usage
#   /superadmin/finances/stripe         does it all match Stripe?
#   /superadmin/finances/orgs/:org_id   one org, all of it
module Superadmin
  class FinancesController < ApplicationController
    before_action :require_superadmin
    before_action :use_superadmin_sidebar

    def cocoscout
      @finances = CocoScoutFinances.new(params[:period])
      @check = PlatformReconciliation.latest
      respond_to do |format|
        format.html
        format.csv do
          send_data ledger_csv(@finances.entries.includes(:organization).order(:occurred_at)),
                    filename: "cocoscout-ledger-#{@finances.period}-#{Date.current.iso8601}.csv", type: "text/csv"
        end
      end
    end

    def organizations
      month = Date.current.beginning_of_month.beginning_of_day..Time.current
      ids = (OrgCashEntry.distinct.pluck(:organization_id) + BillingInvoice.distinct.pluck(:organization_id) +
             CocoScoutLedgerEntry.where.not(organization_id: nil).distinct.pluck(:organization_id) +
             Organization.where(comped_indefinitely: true).or(Organization.where(comped_until: Time.current..))
                         .or(Organization.where(subscription_status: SubscriptionSyncService::ACCESS_STATUSES)).pluck(:id)).uniq
      paid_us = CocoScoutLedgerEntry.where(organization_id: ids, occurred_at: month, entry_type: CocoScoutLedgerEntry.types_in(:income))
                                    .group(:organization_id).sum(:amount_cents)
      unpaid = BillingInvoice.unpaid.where(organization_id: ids).group(:organization_id).sum(:amount_remaining_cents)
      @rows = Organization.where(id: ids).order(:name).map do |org|
        summary = OrgMoneySummary.new(org)
        { organization: org, held_cents: summary.held_cents, available_cents: summary.balance.available_cents,
          in_flight_cents: summary.in_flight.sum(&:cents), paid_us_cents: paid_us[org.id].to_i, unpaid_cents: unpaid[org.id].to_i }
      end
    end

    def subscriptions
      @orgs = Organization.where(comped_indefinitely: true).or(Organization.where(comped_until: Time.current..))
                          .or(Organization.where.not(subscription_status: [ nil, "" ]))
                          .or(Organization.where.not(staffing_subscription_id: nil))
                          .order(:name).to_a
      month = Date.current
      @usage = @orgs.index_with do |org|
        { performers: PerformerActivation.where(organization: org).for_month(month).count,
          staff: StaffActivation.where(organization: org).for_month(month).count }
      end
      @last_invoices = BillingInvoice.where(organization_id: @orgs.map(&:id)).newest_first.group_by(&:organization_id)
      paying = @orgs.select { |o| !o.comped? && o.subscription_status.in?(SubscriptionSyncService::ACCESS_STATUSES) }
      @mrr_cents = paying.sum { |o| o.subscription_interval == "year" ? (SubscriptionPlan::PRO_ANNUAL_CENTS / 12.0).round : SubscriptionPlan::PRO_MONTHLY_CENTS }
      @paying_count = paying.size
      @comped = @orgs.select(&:comped?)
      @past_due = @orgs.select { |o| o.subscription_status == "past_due" }
      @failed_invoices = BillingInvoice.where(organization_id: @orgs.map(&:id)).select(&:failed?)
    end

    def stripe_check
      @check = PlatformReconciliation.latest
      @history = PlatformReconciliation.newest_first.limit(30)
      @lines = StripeBalanceTransaction.needs_a_look.newest_first.includes(:organization).limit(200)
      @failed_webhooks = WebhookEvent.failed.order(updated_at: :desc).limit(50)
      @last_import_at = StripeBalanceTransaction.maximum(:updated_at)
      @opening = CocoScoutLedgerEntry.find_by(entry_type: "opening_difference")
      @recent = StripeBalanceTransaction.newest_first.includes(:organization).limit(50)
    end

    def run_check
      PlatformCheckNowJob.perform_later
      redirect_to finances_stripe_check_path, notice: "Checking Stripe now. Refresh in a minute for the result."
    end

    def explain_line
      row = StripeBalanceTransaction.find(params[:id])
      note = params[:note].to_s.strip
      if note.blank?
        redirect_to finances_stripe_check_path, alert: "Say what it was, so the next person knows."
        return
      end

      row.explain!(note: note, by: Current.user)
      PlatformReconciliationCheck.run!
      redirect_to finances_stripe_check_path, notice: "Explained. It now counts as CocoScout's own money."
    end

    def opening_difference
      row = PlatformReconciliationCheck.run!
      entry = CocoScoutLedgerBackfill.record_opening_difference!(row)
      PlatformReconciliationCheck.run!
      redirect_to finances_stripe_check_path,
                  notice: entry ? "Recorded #{helpers.number_to_currency(entry.amount_cents / 100.0)} as the opening difference." : "Nothing to record."
    end

    def organization
      @org = Organization.find(params[:org_id])
      @summary = OrgMoneySummary.new(@org)
      @statements = @org.org_statements.newest_first.limit(24)
    end

    def statement
      statement = OrgStatement.find(params[:id])
      return head :not_found unless statement.pdf.attached?

      send_data statement.pdf.download, filename: statement.filename, type: "application/pdf", disposition: "inline"
    end

    # CocoScout's invoice for any organization's bill, as the org sees it.
    def invoice
      bill = BillingInvoice.find(params[:id])
      send_data InvoicePdf.new(CocoScoutInvoice.document(bill)).render, filename: CocoScoutInvoice.filename(bill),
                                                                         type: "application/pdf", disposition: "inline"
    end

    # Make (or remake) a statement for a month without emailing it.
    def make_statement
      org = Organization.find(params[:org_id])
      month = Date.iso8601(params[:month].presence || Date.current.prev_month.beginning_of_month.iso8601)
      OrgStatementJob.perform_later(org.id, month.beginning_of_month.iso8601, email: false)
      redirect_to finances_org_detail_path(org_id: org.id), notice: "Making the #{month.strftime('%B %Y')} statement. Refresh in a moment."
    rescue Date::Error
      redirect_to finances_org_detail_path(org_id: params[:org_id]), alert: "Pick a month."
    end

    private

    def use_superadmin_sidebar
      @show_my_sidebar = false
      @show_manage_sidebar = false
      @show_manage_header_only = false
      @show_group_sidebar = false
      @show_account_sidebar = false
      @show_superadmin_sidebar = true
    end

    def ledger_csv(entries)
      require "csv"
      CSV.generate do |csv|
        csv << [ "Date", "Kind", "Organization", "Amount", "Description" ]
        entries.find_each do |entry|
          csv << [ entry.occurred_at.in_time_zone.to_date.iso8601, entry.label, entry.organization&.name,
                   format("%.2f", entry.amount_cents / 100.0), entry.description ]
        end
      end
    end
  end
end
