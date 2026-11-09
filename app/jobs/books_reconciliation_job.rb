# frozen_string_literal: true

# Nightly: every organization with books gets them checked against the
# records they summarize (BooksReconciliation). A mismatch is logged, kept
# on the organization for its Books pages to show, and told to CocoScout's
# superadmins as a notification when it is new or has changed since they
# were last told (BooksNotices.books_disagree; until 2026-11-09 the log was
# the only place it went). Nothing is changed automatically.
class BooksReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    news = []
    Organization.where(id: JournalEntry.select(:organization_id).distinct).find_each do |organization|
      # The month-end balances first: checked against the lines they stand
      # for (thrown away if they ever disagree), then the months that
      # finished since are kept.
      off = BooksBalances.verify!(organization)
      Rails.logger.error("[BooksBalances] org #{organization.id}: kept month-end balances disagreed with the lines for accounts #{off.join(', ')}; rebuilt") if off.any?
      BooksBalances.roll!(organization)
      mismatches = BooksReconciliation.record!(organization)
      mismatches.each do |mismatch|
        Rails.logger.error("[BooksReconciliation] org #{organization.id} #{mismatch.account}: books " \
                           "#{mismatch.books_cents}¢ vs expected #{mismatch.expected_cents}¢ " \
                           "(off by #{mismatch.difference_cents}¢)")
      end
      next unless BooksReconciliation.news?(organization, mismatches)

      news << [ organization, mismatches ]
      BooksReconciliation.told!(organization, mismatches)
    end
    # A laptop's copy of production never agrees for long, and its pushes
    # would reach real phones: only production's check is worth telling.
    BooksNotices.books_disagree(news) unless Rails.env.development?
  end
end
