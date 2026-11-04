# frozen_string_literal: true

module Manage
  # Settle up (Books V1.3, plan §9.2): the days that had money in them, and
  # one worksheet per day. Each show's piece is its Show Financials, checked
  # with "Looks right"; door cash is counted here; the day is settled when
  # every piece is checked, and can be reopened with a reason (§9.7).
  class SettlementDaysController < Manage::ManageController
    before_action :set_date, except: :index
    before_action :require_change!, only: %i[settle reopen door_cash check_show check_register tips]

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
      # The day picker Home has: earlier, the day (a two-month calendar), later, Today.
      @today = SettlementDay.day_for(Current.organization, Time.current)
      @calendar_months = calendar_months_around(@date)
      @day_states = SettleUp.date_states(Current.organization, @calendar_months.first..@calendar_months.last.end_of_month)
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

    def check_register
      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      record.register_checked_at = params[:checked] == "1" ? Time.current : nil
      record.save!
      redirect_to manage_money_settle_up_day_path(@date), notice: (params[:checked] == "1" ? "Register checked." : "Register unchecked.")
    end

    # The day's tips: how they're split, each person's share and how it's
    # paid, and whether someone has checked the section.
    def tips
      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      by_rule = params[:mode] == "rule"
      record.tips_split = by_rule ? "rule" : (params[:split].presence_in(%w[even hours typed]) || "even")
      record.tips_checked_at = params[:checked] == "1" ? Time.current : nil
      record.save!
      given = params.fetch(:shares, {}).to_unsafe_h
      people = Person.where(id: given.keys.map(&:to_i)).index_by(&:id)
      given.each do |person_id, attrs|
        person = people[person_id.to_i]
        next unless person

        share = record.tip_shares.find_or_initialize_by(person: person)
        next if share.payout_contribution_id.present?

        cents = cents_from(attrs["amount"])
        if by_rule
          save_rule_share(share, attrs, cents)
        elsif cents.positive?
          # Only a split the manager chose to type is "typed"; an even or
          # by-hours split the page suggested is the page's own, so a rule
          # turned on later works it out again instead of keeping it.
          share.update!(amount_cents: cents, method: attrs["method"].presence_in(TipShare::METHODS) || "payout",
                        source: record.tips_split == "typed" ? "typed" : "computed")
        elsif share.persisted?
          share.destroy!
        end
      end
      add_person_to_tips(record, params[:new_share]) if params.dig(:new_share, :person_id).present?
      write_computed_shares(record) if by_rule || record.tip_shares.where.not(worked_from: nil).exists?
      redirect_to manage_money_settle_up_day_path(@date), notice: "Tips saved."
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

    # One row of the worked-out split, as the worksheet sent it back (§9.14):
    # taken off, a span changed, a share typed over, or left as worked out.
    def save_rule_share(share, attrs, cents)
      if attrs["remove"] == "1"
        share.destroy! if share.persisted?
        return
      end

      share.source = "computed" if share.new_record?
      share.method = attrs["method"].presence_in(TipShare::METHODS) || share.method || "payout"
      share.house_role_id = attrs["house_role_id"].presence || share.house_role_id
      from, to = span_from(attrs["from"], attrs["to"])
      span_words = [ attrs["from"], attrs["to"] ].join("-")
      if from && to && (attrs["span_shown"].blank? || span_words != attrs["span_shown"])
        share.worked_from = from
        share.worked_to = to
      end
      if params[:recompute] == "1"
        share.source = "computed"
      elsif attrs["shown"].present? && cents != cents_from(attrs["shown"])
        share.source = "typed"
      end
      share.amount_cents = cents
      share.save!
    end

    # Add a person and the span they worked, straight from the worksheet.
    def add_person_to_tips(record, attrs)
      person = Current.organization.organization_staff_members.active.find_by(person_id: attrs[:person_id])&.person
      from, to = span_from(attrs[:from], attrs[:to])
      return unless person && from && to

      share = record.tip_shares.find_or_initialize_by(person: person)
      return if share.payout_contribution_id.present?

      share.assign_attributes(worked_from: from, worked_to: to, house_role_id: attrs[:house_role_id].presence, source: "computed", method: share.method || "payout")
      share.save!
    end

    # The split worked out again from the shares as they now stand, written
    # back so settling the day sends each share where it goes.
    def write_computed_shares(record)
      tips = SettleUp.day(Current.organization, @date).tips
      return unless tips.by_rule?

      tips.rows.each do |row|
        next if row.locked?

        share = record.tip_shares.find_or_initialize_by(person: row.person)
        share.assign_attributes(amount_cents: row.cents, source: row.source, method: row.method, house_role_id: row.house_role&.id)
        share.save!
      end
      # A share for anyone the rule leaves out (an older even split, a role
      # taken out of the rule since) goes: settling pays the rows, nothing else.
      record.tip_shares.where(payout_contribution_id: nil).where.not(person_id: tips.rows.map { |r| r.person.id }).destroy_all
    end

    # "18:00" and "01:30" on the day's own clock: anything before the day
    # starts is the small hours of the night after.
    def span_from(from_text, to_text)
      from = clock_on_day(from_text)
      to = clock_on_day(to_text)
      return nil unless from && to

      to += 1.day if to <= from
      [ from, to ]
    end

    def clock_on_day(text)
      return nil unless text.to_s.match?(/\A\d{1,2}:\d{2}\z/)

      hour, minute = text.split(":").map(&:to_i)
      window = SettlementDay.window(Current.organization, @date)
      time = @date.in_time_zone.change(hour: hour, min: minute)
      time += 1.day if time < window.begin
      time
    end

    def cents_from(text) = (text.to_s.delete("$,").to_f * 100).round

    def set_date
      @date = Date.iso8601(params[:date])
    rescue ArgumentError
      redirect_to manage_money_settle_up_path
    end

    def require_change!
      starts = Current.organization.settle_up_starts_on
      if starts && @date < starts
        return redirect_to manage_money_settle_up_day_path(@date), alert: "This day is before Settle up started (#{starts.strftime('%b %-d, %Y')}). It stays as it was."
      end
      return if OrganizationAccess.allows?(Current.user, Current.organization, :settle_up, :manage)

      redirect_to manage_money_settle_up_day_path(@date), alert: "You can look at this day but not change it."
    end
  end
end
