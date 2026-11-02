# frozen_string_literal: true

module Manage
  # Bank rules (Books V1.3, plan D3; Tim, 2026-11-02): made, changed, removed
  # and applied from the bank page's Rules modal. A new or changed rule
  # runs over the lines waiting right away; a big run goes to the
  # background. Changing needs manage on Books.
  class BankRulesController < Manage::ManageController
    before_action :require_change!
    before_action :set_rule, only: %i[update destroy]

    # How many lines waiting a rule as typed would fit (JSON, for the form).
    def preview
      render json: BankRules.preview(Current.organization, contains: params[:contains].to_s, direction: params[:direction].to_s)
    end

    def create
      rule = Current.organization.bank_rules.new(rule_params.merge(created_by: Current.user))
      return redirect_to manage_money_bank_path, alert: "The rule wasn't saved: #{rule.errors.full_messages.to_sentence}." unless rule.save

      run(rule, "Rule saved.")
    end

    def update
      return redirect_to manage_money_bank_path, alert: "The rule wasn't changed: #{@rule.errors.full_messages.to_sentence}." unless @rule.update(rule_params)

      run(@rule, "Rule changed.")
    end

    def destroy
      @rule.destroy!
      redirect_to manage_money_bank_path, notice: "Rule removed. What it already did stays as it is."
    end

    # Every rule over every line waiting, or one rule (id) by itself.
    def apply
      run(params[:id].present? ? Current.organization.bank_rules.find(params[:id]) : nil, nil)
    end

    # A suggested rule (BankRuleSuggestions) taken: made, run over the lines
    # waiting, and the Rules modal told, without leaving the page.
    def accept
      org = Current.organization
      rule = org.bank_rules.new(suggestion_params.merge(created_by: Current.user))
      return redirect_to manage_money_bank_path, alert: "The rule wasn't saved: #{rule.errors.full_messages.to_sentence}." unless rule.save

      lines = rule.waiting_lines
      note = if lines.empty?
        "Rule saved. It fits none of the lines waiting; it'll run on statements brought in later."
      elsif lines.size <= BankRules::IN_REQUEST
        result = BankRules.apply!(org, rules: [ rule ], lines: lines, by: Current.user)
        "Rule saved. #{pluralize(result.dealt_with, 'line')} dealt with: #{result.recorded} recorded, #{result.ignored} ignored."
      else
        Rails.cache.write(BankRules.applying_key(org), Time.current.to_i, expires_in: 20.minutes)
        BankRulesApplyJob.perform_later(org.id, Current.user.id, rule.id)
        "Rule saved. #{pluralize(lines.size, 'line')} fit; they're being dealt with in the background."
      end
      respond_to do |format|
        format.turbo_stream { render partial: "manage/bank_statements/suggestion_taken", formats: [ :turbo_stream ], locals: { key: params[:key].to_s, note: note, changed: lines.any? } }
        format.html { redirect_to manage_money_bank_path, notice: note }
      end
    end

    # A suggestion said no to: not suggested again.
    def dismiss
      Current.organization.bank_rule_dismissals.find_or_create_by!(phrase: params[:phrase].to_s, direction: params[:direction].presence_in(BankRule::DIRECTIONS) || "any") do |d|
        d.dismissed_by = Current.user
      end
      respond_to do |format|
        format.turbo_stream { render partial: "manage/bank_statements/suggestion_taken", formats: [ :turbo_stream ], locals: { key: params[:key].to_s, note: nil, changed: false } }
        format.html { redirect_to manage_money_bank_path, notice: "Not suggested again." }
      end
    end

    private

    # Runs one rule, or all of them, over the lines waiting: now when there
    # are few, in the background when there are many.
    def run(rule, saved)
      org = Current.organization
      rules = rule ? [ rule ] : org.bank_rules.order(:id).to_a
      lines = org.bank_statement_lines.to_deal_with.to_a.select { |line| rules.any? { |r| r.matches?(line) } }
      lead = saved ? "#{saved} " : ""
      if lines.empty?
        redirect_to manage_money_bank_path, notice: "#{lead}#{rule ? 'It fits none of the lines waiting' : 'No rule fits any of the lines waiting'}; it'll run on statements brought in later."
      elsif lines.size <= BankRules::IN_REQUEST
        result = BankRules.apply!(org, rules: rules, lines: lines, by: Current.user)
        redirect_to manage_money_bank_path, notice: "#{lead}#{pluralize(result.dealt_with, 'line')} dealt with: #{result.recorded} recorded, #{result.ignored} ignored."
      else
        Rails.cache.write(BankRules.applying_key(org), Time.current.to_i, expires_in: 20.minutes)
        BankRulesApplyJob.perform_later(org.id, Current.user.id, rule&.id)
        redirect_to manage_money_bank_path, notice: "#{lead}#{pluralize(lines.size, 'line')} fit; they're being dealt with in the background, and you'll get a notification when that's done."
      end
    end

    def rule_params
      params.require(:bank_rule).permit(:contains, :direction, :action, :category_key, :counterparty, :production_id, :on_import)
    end

    # rule_action, since params[:action] is this action's own name.
    def suggestion_params
      params.permit(:contains, :direction, :rule_action, :category_key, :counterparty).to_h.symbolize_keys.then { |h| h.merge(action: h.delete(:rule_action)) }
    end

    def set_rule
      @rule = Current.organization.bank_rules.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_bank_path, alert: "You can look at the bank page but not change it."
    end

    def pluralize(n, word) = "#{n} #{n == 1 ? word : word.pluralize}"
  end
end
