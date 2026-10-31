# frozen_string_literal: true

module Manage
  # Settle up (Books V1.3, plan §9.2): the days that had money in them, and
  # one worksheet per day. Each show's piece is its Show Financials, checked
  # with "Looks right"; door cash is counted here; the day is settled when
  # every piece is checked, and can be reopened with a reason (§9.7).
  class SettlementDaysController < Manage::ManageController
    before_action :set_date, except: :index
    before_action :require_change!, only: %i[settle reopen door_cash check_show]

    def index
      @filter = params[:filter].presence_in(%w[to_settle settled all]) || "to_settle"
      @month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : Date.current.beginning_of_month
      @to_settle = SettleUp.to_settle(Current.organization)
      @month_days = SettleUp.days(Current.organization, @month..@month.end_of_month)
    rescue ArgumentError
      redirect_to manage_money_settle_up_path
    end

    def show
      @day = SettleUp.day(Current.organization, @date)
      @prev_day = SettleUp.days(Current.organization, (@date - 90)..(@date - 1)).first
      @next_day = SettleUp.days(Current.organization, (@date + 1)..(@date + 90)).last
      @month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : @date.beginning_of_month
      @month_days = SettleUp.days(Current.organization, @month..@month.end_of_month).index_by(&:date)
      @ticket_sources = Current.organization.ticket_sources.hand_made.active.ordered.to_a
    end

    # "Looks right" on a show: its financials are confirmed as they stand.
    def check_show
      show = Show.joins(:production).where(productions: { organization_id: Current.organization.id }).find(params[:show_id])
      financials = show.show_financials || show.create_show_financials!(revenue_type: "ticket_sales")
      financials.update!(data_confirmed: params[:checked] == "1")
      redirect_to manage_money_settle_up_day_path(@date), notice: (params[:checked] == "1" ? "#{show.display_name} checked." : "#{show.display_name} unchecked.")
    end

    def door_cash
      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      counted = params[:counted].to_s.strip
      record.door_cash = {
        "counted_cents" => (counted.present? ? (counted.delete("$,").to_f * 100).round : nil),
        "float_kept_cents" => (params[:float_kept].to_s.delete("$,").to_f * 100).round,
        "note" => params[:note].to_s.strip
      }.compact
      record.save!
      redirect_to manage_money_settle_up_day_path(@date), notice: "Door cash saved."
    end

    def settle
      day = SettleUp.day(Current.organization, @date)
      unless day.all_checked?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "Check every piece first; #{day.checked_count} of #{day.pieces.size} are checked."
      end

      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      record.settle!(by: Current.user)
      SettlementPoster.post!(record)
      redirect_to manage_money_settle_up_day_path(@date), notice: "#{@date.strftime('%A, %B %-d')} is settled."
    end

    def reopen
      record = SettlementDay.find_by!(organization: Current.organization, date: @date)
      if params[:reason].to_s.strip.blank?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "Say why the day is being reopened."
      end

      record.reopen!(by: Current.user, reason: params[:reason])
      SettlementPoster.unpost!(record)
      redirect_to manage_money_settle_up_day_path(@date), notice: "#{@date.strftime('%A, %B %-d')} is open again. Settle it when it's right."
    end

    private

    def set_date
      @date = Date.iso8601(params[:date])
    rescue ArgumentError
      redirect_to manage_money_settle_up_path
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :settle_up, :manage)

      redirect_to manage_money_settle_up_day_path(@date), alert: "You can look at this day but not change it."
    end
  end
end
