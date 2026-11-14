# frozen_string_literal: true

module Manage
  # Settle up (Books V1.3, plan §9.2): the days that had money in them, and
  # one worksheet per day. Each show's piece is its Show Financials, checked
  # with "Looks right"; door cash is counted here; the day is settled when
  # every piece is checked, and can be reopened with a reason (§9.7).
  class SettlementDaysController < Manage::ManageController
    before_action :set_date, except: :index
    before_action :require_change!, only: %i[settle reopen check_show check_register tips tips_preview choose_calculation calculate_show pay_line]

    LISTED = 60

    def index
      @filter = params[:filter].presence_in(%w[to_settle settled all]) || "to_settle"
      @month = params[:month].present? ? Date.strptime(params[:month], "%Y-%m") : Date.current.beginning_of_month
      # Only the list being looked at is built: the days to settle (the
      # oldest LISTED of them), or the month's.
      @open_dates = SettleUp.open_dates(Current.organization)
      @to_settle = @filter == "to_settle" ? SettleUp.to_settle(Current.organization, limit: LISTED) : []
      @month_days = @filter == "to_settle" ? [] : SettleUp.days(Current.organization, @month..@month.end_of_month)
      # Today, while it's still going (Tim, 2026-11-13: "I should be able to
      # start with settling today up. Not just if it's in the past"): at the
      # top of To settle from the moment it has a show or a register day, so
      # nobody goes to All days to find it. It isn't counted as a day to
      # settle anywhere (Home, the Money hub) until it's over.
      if @filter == "to_settle"
        today = SettleUp.day(Current.organization, SettlementDay.day_for(Current.organization, Time.current))
        @today = today if today.any? && !today.settled? && !today.ended? && !today.before_start?
      end
    rescue ArgumentError
      redirect_to manage_money_settle_up_path
    end

    def show
      @day = SettleUp.day(Current.organization, @date)
      # The show whose "Who gets paid" is open on arrival (after a choice on one of its lines, or Calculate).
      @open_show_id = params[:open].to_s
      # A modal to arrive with open, when a choice was made from inside it (the chooser, from Who's paid and how).
      @open_modal_id = params[:modal].to_s
      # The nearest day with money in it each way: their dates are all the
      # arrows need, so no day is built for them.
      @prev_date = SettleUp.dates(Current.organization, (@date - 90)..(@date - 1)).max
      @next_date = SettleUp.dates(Current.organization, (@date + 1)..(@date + 90)).min
      # The day picker Home has: earlier, the day (a two-month calendar), later, Today.
      @today = SettlementDay.day_for(Current.organization, Time.current)
      @calendar_months = calendar_months_around(@date)
      @day_states = SettleUp.date_states(Current.organization, @calendar_months.first..@calendar_months.last.end_of_month)
      @ticket_sources = Current.organization.ticket_sources.hand_made.active.ordered.to_a
    end

    # Confirm on a show (Tim, 2026-11-04: "I confirm this", not "looks
    # right"): its financials are confirmed as they stand. It waits while the
    # pay side has a question open (no calculation chosen, act counts to
    # enter, the payout not worked out yet or worked out from older numbers).
    # Confirming restamps the calculation, so the confirm itself never reads
    # as the numbers changing.
    def check_show
      show = find_show
      financials = show.show_financials || show.create_show_financials!(revenue_type: "ticket_sales")
      checking = params[:checked] == "1"
      pay = SettleUp.pay_for(Current.organization, show)
      if checking && pay.held?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "#{pay.hold_reason}; then #{show.display_name} can be confirmed."
      end

      financials.update!(data_confirmed: checking)
      pay.show_payout.update_column(:calculated_at, Time.current) if pay.calc == :current
      redirect_to manage_money_settle_up_day_path(@date), notice: (checking ? "#{show.display_name} confirmed." : "#{show.display_name} unconfirmed.")
    end

    # The Calculate step (Tim, 2026-11-04): work out who gets paid from the
    # numbers as they stand, or work it out again once they changed. Each
    # line keeps its choice. The card opens on what it found.
    def calculate_show
      show = find_show
      result = SettlementPayer.calculate!(show)
      if result[:success]
        count = result[:line_items].map(&:pay_choice_key).uniq.size
        redirect_to manage_money_settle_up_day_path(@date, open: show.id), notice: "#{show.display_name}: #{helpers.number_to_currency(result[:total])} to #{count} #{"person".pluralize(count)}."
      else
        redirect_to manage_money_settle_up_day_path(@date, open: show.id), alert: "#{show.display_name} couldn't be worked out: #{result[:error]}."
      end
    end

    # How a show's performers are paid, asked on the day when nothing says
    # yet (Tim, 2026-11-04): one of the organization's calculations, for
    # every show of the production from now on or just this one (then the
    # production asks for each show); or nobody is paid from this
    # production's shows. A new calculation is made in the wizard, which
    # comes back here.
    def choose_calculation
      show = find_show
      production = show.production
      if params[:choice] == "nobody"
        production.update!(pays_performers: false)
        ShowPayout.restamp_pending_for_production!(production, nil)
        return redirect_to manage_money_settle_up_day_path(@date, open: show.id), notice: "No performers are paid for #{production.name}; its shows settle without a payout. Set up a payout, on the show's card, turns it back on."
      end
      # The way back from "nobody is paid" (Tim, 2026-11-04: it can be a slip): performer pay goes back on, and the question is asked again.
      if params[:choice] == "pay_after_all"
        production.update!(pays_performers: true)
        return redirect_to manage_money_settle_up_day_path(@date, open: show.id), notice: "#{production.name} pays its performers again. Say how, on the show's card."
      end

      scheme = Current.organization.payout_schemes.active.find_by(id: params[:payout_scheme_id])
      return redirect_to manage_money_settle_up_day_path(@date), alert: "Pick a calculation to use." unless scheme

      payout = show.show_payout
      locked = payout&.line_items&.any? { |line| line.paid? || line.in_payout_run? }
      if params[:scope] == "show"
        production.update!(payout_calculation_mode: "each_show", pays_performers: true)
        payout ||= show.create_show_payout!(status: "awaiting_payout")
        payout.update!(payout_scheme: scheme, override_rules: nil) unless locked
        notice = "#{show.display_name} uses #{scheme.name}. You'll be asked for each #{production.name} show."
      else
        production.update!(payout_calculation_mode: "production", pays_performers: true)
        scheme.make_production_scheme!(production)
        payout&.update!(payout_scheme: scheme, override_rules: nil) unless locked
        notice = "Every #{production.name} show uses #{scheme.name} from now on."
      end
      # A show already worked out is worked out again on the new calculation, each line keeping its choice.
      if payout&.calculated_at.present? && !locked
        result = SettlementPayer.calculate!(show.reload)
        notice += result[:success] ? " #{show.display_name}: #{helpers.number_to_currency(result[:total])} to #{result[:line_items].size} #{'person'.pluralize(result[:line_items].size)}." : " It couldn't be worked out again: #{result[:error]}."
      elsif locked
        notice += " #{show.display_name}'s lines are paid or on a run, so they stay as they are."
      end
      redirect_to manage_money_settle_up_day_path(@date, open: show.id, modal: params[:reopen].presence), notice: notice
    end

    # One line's choice: on the run when the day settles, or held for now.
    def pay_line
      show = find_show
      line = show.show_payout&.line_items&.find_by(id: params[:line_id])
      return redirect_to manage_money_settle_up_day_path(@date), alert: "That line isn't on this show any more." unless line
      if line.paid? || line.in_payout_run?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "#{line.payee_name}'s line is #{line.paid? ? 'already paid' : 'already on a run'}."
      end

      line.update!(pay_choice: params[:pay_choice].presence_in(ShowPayoutLineItem::PAY_CHOICES) || "run")
      redirect_to manage_money_settle_up_day_path(@date, open: show.id), notice: "#{line.payee_name}: #{line.held? ? 'held for now' : 'on the run when the day settles'}."
    end

    # "Looks right" on the register card covers the tips on it too (Tim,
    # 2026-11-03: tips from Square belong in the Square card). Checking
    # writes the split as it stands, so settling pays the rows; it waits
    # while a stretch with nobody on the bar has no answer yet.
    def check_register
      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      checking = params[:checked] == "1"
      if checking
        tips = SettleUp.day(Current.organization, @date).tips
        if tips.unresolved.any?
          return redirect_to manage_money_settle_up_day_path(@date), alert: "Say who gets the tips rung up with nobody on the bar first: Change the split on the register."
        end
        if tips.undecided?
          return redirect_to manage_money_settle_up_day_path(@date), alert: "Say who gets the tips first: Change the split on the register."
        end
      end
      record.register_checked_at = checking ? Time.current : nil
      record.tips_checked_at = record.register_checked_at
      record.save!
      write_tip_shares(record) if checking
      redirect_to manage_money_settle_up_day_path(@date), notice: (checking ? "Register confirmed." : "Register unconfirmed.")
    end

    # The day's tips: how they're split, each person's share and how it's
    # paid, and who gets each stretch with nobody on the bar.
    def tips
      apply_tip_changes!
      redirect_to manage_money_settle_up_day_path(@date), notice: "Tips saved."
    end

    # The tips modal, worked out again with what it holds now, and nothing
    # saved (Tim, 2026-11-13): add someone or take someone off and the
    # shares change in front of you; Save the split is what keeps them. The
    # same changes Save makes, run and rolled back, so the two never differ.
    def tips_preview
      html = nil
      ActiveRecord::Base.transaction do
        apply_tip_changes!
        day = SettleUp.day(Current.organization, @date)
        tips = day.tips
        roles_by_id = tips.rule&.enabled? ? Current.organization.house_roles.index_by(&:id) : {}
        html = render_to_string(partial: "manage/settlement_days/tips_modal", formats: [ :html ],
                                locals: { id: params[:modal_id].presence || "tips-split-#{day.param}", day: day, tips: tips,
                                          hand_rows: tips.hand_rows, roles_by_id: roles_by_id, carried: tip_carry_over })
        raise ActiveRecord::Rollback
      end
      render html: html
    end

    def settle
      day = SettleUp.day(Current.organization, @date)
      unless day.all_checked?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "Confirm every piece first; #{day.checked_count} of #{day.checks.size} are confirmed."
      end

      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      record.settle!(by: Current.user)
      SettlementPoster.post!(record)
      # Settling is what puts the day's payouts on the open run (Tim, 2026-11-04).
      staged = SettlementPayer.stage!(day, by: Current.user)
      notice = "#{@date.strftime('%A, %B %-d')} is settled."
      notice += " #{staged.words} went on the draft payout run." if staged.any?
      notice += " #{staged.notes.join(' ')}" if staged.notes.any?
      redirect_to manage_money_settle_up_day_path(@date), notice: notice
    end

    def reopen
      record = SettlementDay.find_by!(organization: Current.organization, date: @date)
      if params[:reason].to_s.strip.blank?
        return redirect_to manage_money_settle_up_day_path(@date), alert: "Say why the day is being reopened."
      end

      # Reopening undoes what settling did, all of it or none (a failure
      # part way must not leave the day open with its tips still on a run):
      # the books, the tips (off a draft run, and no longer waiting on Pay
      # People), and, unless the modal says to keep them, the day's payouts
      # on the draft run (Tim, 2026-11-04). Off is the default.
      notice = "#{@date.strftime('%A, %B %-d')} is open again."
      ActiveRecord::Base.transaction do
        waiting = record.tip_shares.where(payout_contribution_id: nil, method: "payout").where("amount_cents > COALESCE(paid_cents, 0)").count
        record.reopen!(by: Current.user, reason: params[:reason])
        tipped = SettlementPoster.unpost!(record)
        if params[:payouts] == "keep"
          notice += " Its payouts stayed on the draft payout run."
        else
          taken = SettlementPayer.unstage!(SettleUp.day(Current.organization, @date))
          notice += " #{taken.words} came off the draft payout run; it goes back on when the day settles." if taken.any?
        end
        notice += " #{tipped.map { |name| "#{name}'s" }.to_sentence} tips came off the draft payout run." if tipped.any?
        notice += " Its tips stopped waiting on Pay People." if waiting.positive?
      end
      redirect_to manage_money_settle_up_day_path(@date), notice: "#{notice} Settle it when it's right."
    end

    private

    # What the preview's form has to carry to Save, since the preview saved
    # nothing: who was taken off, whose share was typed, and each span as the
    # page first showed it (so Save still tells a changed span from one left
    # alone).
    def tip_carry_over
      given = params.fetch(:shares, {}).to_unsafe_h
      removed = given.select { |_, attrs| attrs["remove"] == "1" }.keys.map(&:to_i)
      typed = given.select { |_, attrs| attrs["typed"] == "1" || (attrs["shown"].present? && cents_from(attrs["amount"]) != cents_from(attrs["shown"])) }.keys.map(&:to_i)
      spans = given.to_h { |pid, attrs| [ pid.to_i, attrs["span_shown"].to_s ] }
      { removed: removed, typed: params[:recompute] == "1" ? [] : typed, spans: spans, added: params.dig(:new_share, :person_id).presence&.to_i }
    end

    # Everything the modal changes, from what it sent: the split, the
    # stretches with nobody on, each share, and someone added.
    def apply_tip_changes!
      record = SettlementDay.find_or_initialize_by(organization: Current.organization, date: @date)
      by_rule = params[:mode] == "rule"
      record.tips_split = by_rule ? "rule" : (params[:split].presence_in(%w[even hours typed]) || "even")
      record.tips_unstaffed = unstaffed_choices(record) if params[:unstaffed].present?
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
          share.drop!
        end
      end
      add_person_to_tips(record, params[:new_share]) if params.dig(:new_share, :person_id).present?
      write_tip_shares(record) if by_rule || record.tip_shares.where.not(worked_from: nil).exists?
    end

    # One row of the worked-out split, as the worksheet sent it back (§9.14):
    # taken off, a span changed, a share typed over, or left as worked out.
    def save_rule_share(share, attrs, cents)
      if attrs["remove"] == "1"
        share.drop! if share.persisted?
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
      elsif attrs["typed"] == "1" || (attrs["shown"].present? && cents != cents_from(attrs["shown"]))
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

    # unstaffed[<stretch key>] = house | split | <person id>: the answer for
    # each stretch with nobody on, kept with the day; the rest of the day's
    # answers stay as they were.
    def unstaffed_choices(record)
      given = params[:unstaffed].to_unsafe_h.filter_map do |key, choice|
        choice = choice.to_s
        next unless key.to_s.match?(/\A(untimed|\d{4}-\d{2}-\d{2}T[\d:]+Z)\z/)
        next unless choice.in?(%w[house split]) || choice.match?(/\A\d+\z/)

        [ key.to_s, choice ]
      end
      record.tips_unstaffed.merge(given.to_h)
    end

    # The split as it now stands, written back so settling the day pays the
    # rows and nothing else. By the rule: the rows, and anyone the rule
    # leaves out goes. By hand, with nothing saved yet: the suggestion shown.
    def write_tip_shares(record)
      tips = SettleUp.day(Current.organization, @date).tips
      unless tips.by_rule?
        return if record.tip_shares.exists?

        tips.hand_rows.each do |row|
          next unless row[:cents].positive?

          record.tip_shares.create!(person: row[:worker].person, amount_cents: row[:cents], method: row[:method], source: "computed")
        end
        return
      end

      tips.rows.each do |row|
        next if row.locked?

        share = record.tip_shares.find_or_initialize_by(person: row.person)
        share.assign_attributes(amount_cents: row.cents, source: row.source, method: row.method, house_role_id: row.house_role&.id)
        share.save!
      end
      # A share for anyone the rule leaves out (an older even split, a role
      # taken out of the rule since) goes: settling pays the rows, nothing else.
      record.tip_shares.where(payout_contribution_id: nil).where.not(person_id: tips.rows.map { |r| r.person.id }).each(&:drop!)
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

    def find_show
      Show.joins(:production).where(productions: { organization_id: Current.organization.id }).find(params[:show_id])
    end

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
