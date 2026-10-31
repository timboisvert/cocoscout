# frozen_string_literal: true

# The one list of money categories (config/money_categories.yml): income
# kinds and spending categories, each with the account it posts to. An
# organization's own categories (Money settings → Books) are non-system
# LedgerAccounts and show up in the same lists under the key "account_<id>".
#
#   MoneyCategories.spending_options(organization)   # [[label, key], ...]
#   MoneyCategories.account_for("venue")             # => :venue
#   MoneyCategories.label_for("talent")              # => "Performer pay"
class MoneyCategories
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
      options_for(spending, organization, "expense")
    end

    def income_options(organization = nil)
      options_for(income, organization, "income")
    end

    # Backwards-compatible name used by Show Financials.
    def options_for_select(organization = nil)
      spending_options(organization)
    end

    def keys = spending_keys

    private

    def options_for(list, organization, account_type)
      system = list.map { |key, data| [ data["label"], key ] }
      return system if organization.nil?

      custom = organization.ledger_accounts.active.where(system: false, account_type: account_type).order(:name)
                           .map { |a| [ a.name, "account_#{a.id}" ] }
      # Other stays last.
      system[0...-1] + custom + system[-1..]
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
