# frozen_string_literal: true

module Manage
  # Bank rules (Books V1.3, plan D3; Tim, 2026-11-02, a page of their own
  # since 2026-11-03): the Rules page lists the payees without a rule and
  # the rules there are; a rule is made or changed on a page of its own,
  # which lists the lines it will catch as the phrase is typed. A new or
  # changed rule runs over the lines waiting right away; a big run goes to
  # the background. Rules go to a file and come back from one, so a set
  # made in development carries to production. Changing needs manage on
  # Books.
  class BankRulesController < Manage::ManageController
    include BooksCategoriesGate
    before_action :require_change!, except: :index
    before_action :set_rule, only: %i[edit update destroy]

    def index
      org = Current.organization
      @summary = BankStatementSummary.new(org)
      @rules = org.bank_rules.includes(:production).order(:id).to_a
      waiting = org.bank_statement_lines.to_deal_with.to_a
      @rule_catches = @rules.to_h { |rule| [ rule.id, waiting.count { |line| rule.matches?(line) } ] }
      @payees = BankSort.payees(org, waiting: waiting, rules: @rules)
      @covered = @payees.sum(&:count)
      @can_change = OrganizationAccess.allows?(Current.user, org, :books, :manage)
    end

    def new
      @rule = Current.organization.bank_rules.new(direction: params[:direction].presence_in(BankRule::DIRECTIONS) || "out", action: "record", on_import: true,
                                                  contains: params[:contains].to_s, category_key: params[:category_key].presence, counterparty: params[:counterparty].presence)
      render :form
    end

    def edit
      render :form
    end

    # How many lines waiting a rule as typed would fit, which ones, and
    # whether the lines already dealt with agree (JSON, for the form).
    def preview
      render json: BankRules.preview(Current.organization, contains: params[:contains].to_s, direction: params[:direction].to_s,
                                                           action: params[:rule_action].to_s, category_key: params[:category_key].to_s)
    end

    def create
      @rule = Current.organization.bank_rules.new(rule_params.merge(created_by: Current.user))
      return render :form, status: :unprocessable_entity unless @rule.save

      run(@rule, "Rule saved.")
    end

    def update
      return render :form, status: :unprocessable_entity unless @rule.update(rule_params)

      run(@rule, "Rule changed.")
    end

    def destroy
      @rule.destroy!
      redirect_to manage_money_bank_rules_path, notice: "Rule removed. What it already did stays as it is."
    end

    # Every rule over every line waiting, or one rule (id) by itself.
    def apply
      run(params[:id].present? ? Current.organization.bank_rules.find(params[:id]) : nil, nil)
    end

    # A payee the person doesn't want a rule for: not offered again.
    def dismiss
      Current.organization.bank_rule_dismissals.find_or_create_by!(phrase: params[:key].to_s, direction: params[:direction].presence_in(BankRule::DIRECTIONS) || "any") do |d|
        d.dismissed_by = Current.user
      end
      redirect_to manage_money_bank_rules_path, notice: "Not offered again. Its lines stay on the bank page to deal with one by one."
    end

    def export
      org = Current.organization
      send_data BankRulesFile.export(org), filename: BankRulesFile.filename(org), type: "application/json"
    end

    def import
      upload = params[:file]
      return redirect_to manage_money_bank_rules_path, alert: "Choose the rules file first." if upload.blank? || !upload.respond_to?(:read)

      result = BankRulesFile.import!(Current.organization, upload.read, by: Current.user)
      parts = [ "#{pluralize(result.added, 'rule')} added" ]
      parts << "#{result.already} already here" if result.already.positive?
      parts << "#{result.skipped} skipped (a category you don't offer, or not a rule)" if result.skipped.positive?
      redirect_to manage_money_bank_rules_path, notice: "#{parts.join(', ')}. Apply them to the lines waiting when you're ready."
    rescue JSON::ParserError, ArgumentError
      redirect_to manage_money_bank_rules_path, alert: "That isn't a CocoScout rules file. Export one from the Rules page of the organization you're copying from."
    end

    private

    # Runs one rule, or all of them, over the lines waiting: now when there
    # are few, in the background when there are many.
    def run(rule, saved)
      org = Current.organization
      rules = rule ? [ rule ] : org.bank_rules.order(:id).to_a
      lines = rule ? rule.waiting_lines : org.bank_statement_lines.to_deal_with.to_a.select { |line| rules.any? { |r| r.matches?(line) } }
      lead = saved ? "#{saved} " : ""
      back = params[:back] == "bank" ? manage_money_bank_path : manage_money_bank_rules_path
      if lines.empty?
        redirect_to back, notice: "#{lead}#{rule ? 'It fits none of the lines waiting' : 'No rule fits any of the lines waiting'}; it'll run on statements brought in later."
      elsif lines.size <= BankRules::IN_REQUEST
        result = BankRules.apply!(org, rules: rules, lines: lines, by: Current.user)
        redirect_to back, notice: "#{lead}#{pluralize(result.dealt_with, 'line')} dealt with: #{result.recorded} recorded, #{result.ignored} ignored."
      else
        Rails.cache.write(BankRules.applying_key(org), Time.current.to_i, expires_in: 20.minutes)
        BankRulesApplyJob.perform_later(org.id, Current.user.id, rule&.id)
        redirect_to back, notice: "#{lead}#{pluralize(lines.size, 'line')} fit; they're being dealt with in the background, and you'll get a notification when that's done."
      end
    end

    def rule_params
      params.require(:bank_rule).permit(:contains, :direction, :action, :category_key, :counterparty, :production_id, :show_id, :on_import)
    end

    def set_rule
      @rule = Current.organization.bank_rules.find(params[:id])
    end

    def require_change!
      return if OrganizationAccess.allows?(Current.user, Current.organization, :books, :manage)

      redirect_to manage_money_bank_rules_path, alert: "You can look at the rules but not change them."
    end

    def pluralize(n, word) = "#{n} #{n == 1 ? word : word.pluralize}"
  end
end
