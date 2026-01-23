class MigrateExpenseDetailsToExpenseItems < ActiveRecord::Migration[8.1]
  def up
    ShowFinancials.where.not(expense_details: nil).find_each do |sf|
      details = sf.expense_details
      # Handle hash format (from form params) or array format
      details = details.values if details.is_a?(Hash)
      next unless details.is_a?(Array)

      details.each_with_index do |item, index|
        next unless item.is_a?(Hash)
        next if item["amount"].to_f <= 0

        ExpenseItem.create!(
          show_financials_id: sf.id,
          category: item["category"].presence || "other",
          description: item["description"],
          amount: item["amount"].to_f,
          position: index
        )
      end
    end
  end

  def down
    # Move expense_items back to expense_details JSONB
    ShowFinancials.includes(:expense_items).find_each do |sf|
      next unless sf.expense_items.any?

      sf.update_column(:expense_details, sf.expense_items.ordered.map do |item|
        {
          "category" => item.category,
          "description" => item.description,
          "amount" => item.amount.to_f
        }
      end)

      sf.expense_items.destroy_all
    end
  end
end
