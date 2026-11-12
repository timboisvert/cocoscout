# frozen_string_literal: true

# Show Financials' name for the spending half of MoneyCategories (the one
# list, config/money_categories.yml). Kept so older views read the same.
class ExpenseCategories
  class << self
    def all = MoneyCategories.spending
    def keys = MoneyCategories.spending_keys
    def options_for_select(organization = nil) = MoneyCategories.spending_options(organization)
    def label_for(key, organization: nil) = MoneyCategories.label_for(key, :spending, organization: organization)
    def icon_for(key) = MoneyCategories.icon_for(key)
  end
end
