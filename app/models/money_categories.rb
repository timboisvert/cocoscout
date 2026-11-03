# frozen_string_literal: true

# The one list of money categories (config/money_categories.yml): income
# kinds and spending categories, each with the account it posts to. An
# organization's own categories (Money settings → Books) are non-system
# LedgerAccounts and show up in the same lists under the key "account_<id>".
# The built-in ones an organization said no to when it set Books up
# (BooksCategorySetup, money_categories_hidden) stay out of the options,
# but a row already in one keeps its label and its account.
#
# The lists come out alphabetical by label, Other last (Tim, 2026-11-02).
#
#   MoneyCategories.spending_options(organization)   # [[label, key], ...]
#   MoneyCategories.spending_choices(organization)   # [Choice(key, label, description), ...]
#   MoneyCategories.account_for("venue")             # => :venue
#   MoneyCategories.label_for("talent")              # => "Performer pay"
class MoneyCategories
  Choice = Struct.new(:key, :label, :description, :custom, keyword_init: true)

  class << self
    def income
      @income ||= config.fetch("income")
    end

    def spending
      @spending ||= config.fetch("spending")
    end

    def income_keys = income.keys
    def spending_keys = spending.keys

    # Old keys (an ExpenseItem typed as "talent", a ProductionExpense as
    # "costumes") read as the category they meant.
    def canonical(key, kind = :spending)
      key = key.to_s
      list = kind == :income ? income : spending
      return key if list.key?(key)

      list.each { |k, data| return k if Array(data["legacy"]).include?(key) }
      key
    end

    def entry(key, kind = :spending)
      return nil if key.to_s.start_with?("account_")

      list = kind == :income ? income : spending
      list[canonical(key, kind)]
    end

    def label_for(key, kind = :spending, organization: nil)
      return custom_account(key, organization)&.name || "Other" if key.to_s.start_with?("account_")

      entry(key, kind)&.fetch("label", nil) || key.to_s.titleize
    end

    def icon_for(key)
      entry(key)&.fetch("icon", nil) || "ellipsis-horizontal-circle"
    end

    # The account a category posts to: a ChartOfAccounts key (Symbol), or
    # the organization's own LedgerAccount for a custom category.
    def account_for(key, kind = :spending, organization: nil)
      if key.to_s.start_with?("account_")
        account = custom_account(key, organization)
        return account if account

        return kind == :income ? :other_income : :other_expenses
      end

      (entry(key, kind)&.fetch("account", nil) || (kind == :income ? "other_income" : "other_expenses")).to_sym
    end

    def spending_options(organization = nil)
      spending_choices(organization).map { |c| [ c.label, c.key ] }
    end

    def income_options(organization = nil)
      income_choices(organization).map { |c| [ c.label, c.key ] }
    end

    # The categories to pick from, with what each is for: the built-in ones
    # the organization offers and its own, alphabetical, Other last.
    def spending_choices(organization = nil)
      choices_for(spending, organization, "expense")
    end

    def income_choices(organization = nil)
      choices_for(income, organization, "income")
    end

    def description_for(key, kind = :spending, organization: nil)
      return custom_account(key, organization)&.description if key.to_s.start_with?("account_")

      entry(key, kind)&.fetch("description", nil)
    end

    # Backwards-compatible name used by Show Financials.
    def options_for_select(organization = nil)
      spending_options(organization)
    end

    def keys = spending_keys

    private

    def choices_for(list, organization, account_type)
      system = list.map { |key, data| Choice.new(key: key, label: data["label"], description: data["description"], custom: false) }
      custom = []
      if organization
        hidden = organization.money_categories_hidden
        if hidden.any?
          kind = account_type == "income" ? "income" : "spending"
          system = system.reject { |c| c.key != "other" && hidden.include?("#{kind}:#{c.key}") }
        end
        custom = organization.ledger_accounts.active.where(system: false, account_type: account_type)
                             .map { |a| Choice.new(key: "account_#{a.id}", label: a.name, description: a.description.presence, custom: true) }
      end
      other, rest = system.partition { |c| c.key == "other" }
      (rest + custom).sort_by { |c| c.label.downcase } + other
    end

    def custom_account(key, organization)
      return nil if organization.nil?

      organization.ledger_accounts.find_by(id: key.to_s.delete_prefix("account_").to_i, system: false)
    end

    def config
      @config ||= YAML.load_file(Rails.root.join("config", "money_categories.yml"))
    end
  end
end
