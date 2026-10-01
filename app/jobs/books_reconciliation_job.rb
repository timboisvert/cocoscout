# frozen_string_literal: true

# Nightly: every organization with books gets them checked against the
# records they summarize (BooksReconciliation). A mismatch is logged loudly
# for us to chase; nothing is changed automatically.
class BooksReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(id: JournalEntry.select(:organization_id).distinct).find_each do |organization|
      BooksReconciliation.check(organization).each do |mismatch|
        Rails.logger.error("[BooksReconciliation] org #{organization.id} #{mismatch.account}: books " \
                           "#{mismatch.books_cents}¢ vs expected #{mismatch.expected_cents}¢ " \
                           "(off by #{mismatch.difference_cents}¢)")
      end
    end
  end
end
