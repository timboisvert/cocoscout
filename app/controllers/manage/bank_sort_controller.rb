# frozen_string_literal: true

module Manage
  # Money → Books → Bank → Sort (Tim, 2026-11-03): what's waiting, one
  # payee at a time and then one line at a time (BankSort). Every answer
  # is done the moment it's given; stopping loses nothing. Needs manage on
  # Books.
  class BankSortController < Manage::ManageController
    include BooksCategoriesGate
    before_action :require_change!

    def show
      org = Current.organization
      @summary = BankStatementSummary.new(org)
      waiting = org.bank_statement_lines.to_deal_with.to_a
      if waiting.empty?
        BankSortPass.where(organization: org, user: Current.user).destroy_all
        @done = true
        return
      end

      @state = state(waiting.size)
      @waiting = waiting.size
      rules = org.bank_rules.to_a
      payees = BankSort.payees(org, waiting: waiting, rules: rules)
      @payee = payees.find { |g| !@state.skipped_payees.include?(g.key) }
      if @payee.nil? && payees.any? && !@state.revisited
        # What was skipped comes back once at the end of part 1.
        @state.skipped_payees = []
        @state.revisited = true
        @payee = payees.first
      end
      if @payee
        @payees_count = payees.size
        @position = payees.index(@payee) + 1
        @siblings = BankPayees.siblings(@payee, BankPayees.groups(org, lines: waiting)).reject { |g| @state.skipped_payees.include?(g.key) }
        @guess = BankSort.guess(org, @payee)
        @productions = org.productions.active.order(:name)
      else
        lines = waiting.reject { |l| @state.skipped_lines.include?(l.id) }
        if lines.empty?
          # What was skipped comes back at the end.
          @state.skipped_lines = []
          lines = waiting
        end
        @line = lines.first
        @left = lines.size
        @reading = @line.payee
        @looks_like = BankStatementSummary.candidates_for(org, [ @line ])[@line.id]
        @hint = @line.description_key && BankStatementSummary.hints_for(org, [ @line ])[@line.description_key]
        @kind = @line.deposit? ? "in" : "out"
        @chips = BankSort.quick_choices(org, @kind)
        @productions = org.productions.active.order(:name)
        @shows = Show.where(production_id: @productions.map(&:id), canceled: false).order(date_and_time: :desc).limit(400).select(:id, :production_id, :date_and_time, :secondary_name)
      end
      save_state
    end

    # Part 1: one payee answered.
    def payee
      org = Current.organization
      waiting = org.bank_statement_lines.to_deal_with.to_a
      @state = state(waiting.size)
      groups = BankPayees.groups(org, lines: waiting)
      group = groups.find { |g| g.key == params[:key].to_s }
      return redirect_to manage_money_bank_sort_path, alert: "That payee is already dealt with." unless group

      taken = [ group ] + groups.select { |g| Array(params[:also]).include?(g.key) && g.direction == group.direction }
      case params[:answer]
      when "record", "ignore"
        rule = BankSort.rule_for(org, taken, action: params[:answer], category_key: params[:category_key], counterparty: params[:counterparty],
                                            on_import: params[:on_import] != "0", by: Current.user)
        return redirect_to manage_money_bank_sort_path, alert: "The rule wasn't saved: #{rule.errors.full_messages.to_sentence}." unless rule.save

        # The lines the matcher found something for stay for part 2, where the match is offered.
        result = BankRules.apply!(org, rules: [ rule ], lines: taken.flat_map(&:open), by: Current.user)
        held = taken.sum { |g| g.suggested.size }
        @state.rules_made += 1
        flash[:notice] = "Rule saved. #{pluralize(result.dealt_with, 'line')} #{rule.ignore? ? 'ignored' : 'recorded'}" \
                         "#{held.positive? ? "; #{held} that look like something on the books come up one by one" : ''}."
      when "varies"
        org.bank_rule_dismissals.find_or_create_by!(phrase: group.key, direction: group.direction) { |d| d.dismissed_by = Current.user }
        flash[:notice] = "No rule for #{group.name}. Its lines come up one by one."
      when "ignore_all"
        group.lines.each { |line| line.ignore! }
        flash[:notice] = "#{pluralize(group.count, 'line')} ignored."
      else
        @state.skipped_payees |= [ group.key ]
      end
      save_state
      redirect_to manage_money_bank_sort_path
    end

    # Part 2: one line answered.
    def line
      org = Current.organization
      @state = state(org.bank_statement_lines.to_deal_with.count)
      line = org.bank_statement_lines.to_deal_with.find_by(id: params[:line_id])
      return redirect_to manage_money_bank_sort_path, alert: "That line is already dealt with." unless line

      reading = line.payee
      case params[:answer]
      when "record"
        record = org.money_records.new(kind: (line.deposit? ? "in" : "out"), on: line.on, amount_cents: line.amount_cents.abs, category_key: params[:category_key].presence,
                                       counterparty: params[:counterparty].to_s.strip.presence, production_id: params[:production_id].presence, show_id: params[:show_id].presence,
                                       via: "bank", memo: line.description, recorded_by: Current.user)
        return redirect_to manage_money_bank_sort_path, alert: "Pick a category first." if record.category_key.blank?
        return redirect_to manage_money_bank_sort_path, alert: "It wasn't recorded: #{record.errors.full_messages.to_sentence}." unless record.save

        line.recorded!(record)
        flash[:notice] = "Recorded as #{record.category_label}#{", #{record.counterparty}" if record.counterparty.present?}."
        make_rule(org, line, reading, "record", category_key: record.category_key, counterparty: record.counterparty, production: record.production, show: record.show)
      when "ignore"
        line.ignore!(note: params[:note])
        flash[:notice] = "Ignored."
        make_rule(org, line, reading, "ignore")
      when "match"
        return redirect_to manage_money_bank_sort_path, alert: "Nothing on the books to match it to." unless line.suggested? && line.all_journal_line_ids.any?

        line.match!(line.journal_lines.to_a)
        flash[:notice] = "Matched."
      else
        @state.skipped_lines |= [ line.id ]
      end
      save_state
      redirect_to manage_money_bank_sort_path
    end

    def stop
      BankSortPass.where(organization: Current.organization, user: Current.user).destroy_all
      redirect_to manage_money_bank_path, notice: "Stopped. Everything you answered is done; come back to Sort any time."
    end

    private

    # "Every time from this payee": a rule, run over the other lines waiting.
    def make_rule(org, line, reading, action, **attrs)
      return unless params[:make_rule] == "1" && reading.rule?

      rule = org.bank_rules.new(contains: reading.phrase, direction: (line.deposit? ? "in" : "out"), action: action, on_import: true, created_by: Current.user, **attrs)
      return unless rule.save

      @state.rules_made += 1
      result = BankRules.apply!(org, rules: [ rule ], lines: org.bank_statement_lines.to_deal_with.where(state: "open").to_a.select { |l| rule.matches?(l) }, by: Current.user)
      flash[:notice] = "#{flash[:notice]} Rule saved for #{reading.name}#{result.dealt_with.positive? ? ", and #{pluralize(result.dealt_with, 'more line')} dealt with" : ''}."
    end

    def state(waiting)
      session.delete(:bank_sort) # the pass lived in the cookie for a day (11/3)
      @state ||= BankSortPass.find_or_initialize_by(organization: Current.organization, user: Current.user).tap { |s| s.total = waiting if s.total < waiting }
    end

    def save_state
      @state&.save!
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_bank_path, alert: "You can look at the bank page but not change it."
    end

    def pluralize(n, word) = "#{n} #{n == 1 ? word : word.pluralize}"
  end
end
