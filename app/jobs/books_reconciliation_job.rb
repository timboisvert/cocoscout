# frozen_string_literal: true

# Nightly: every organization with books gets them checked against the
# records they summarize (BooksReconciliation). A mismatch is logged loudly
# for us to chase and kept on the organization for its Books pages to show;
# nothing is changed automatically.
class BooksReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(id: JournalEntry.select(:organization_id).distinct).find_each do |organization|
      # The month-end balances first: checked against the lines they stand
      # for (thrown away if they ever disagree), then the months that
      # finished since are kept.
      off = BooksBalances.verify!(organization)
      Rails.logger.error("[BooksBalances] org #{organization.id}: kept month-end balances disagreed with the lines for accounts #{off.join(', ')}; rebuilt") if off.any?
      BooksBalances.roll!(organization)
      BooksReconciliation.record!(organization).each do |mismatch|
        Rails.logger.error("[BooksReconciliation] org #{organization.id} #{mismatch.account}: books " \
                           "#{mismatch.books_cents}¢ vs expected #{mismatch.expected_cents}¢ " \
                           "(off by #{mismatch.difference_cents}¢)")
      end
    end
  end
end
