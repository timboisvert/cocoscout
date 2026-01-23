# frozen_string_literal: true

module Manage
  class ExpenseItemsController < Manage::ManageController
    before_action :set_expense_item

    def upload_receipt
      if params[:receipt].present?
        @expense_item.receipt.attach(params[:receipt])
        if @expense_item.save
          render json: { success: true, receipt_url: url_for(@expense_item.receipt) }
        else
          render json: { success: false, error: @expense_item.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      else
        render json: { success: false, error: "No file provided" }, status: :unprocessable_entity
      end
    end

    def remove_receipt
      @expense_item.receipt.purge
      render json: { success: true }
    end

    private

    def set_expense_item
      @expense_item = ExpenseItem.joins(show_financials: { show: :production })
                                 .where(productions: { organization: Current.organization })
                                 .find(params[:id])
    end
  end
end
