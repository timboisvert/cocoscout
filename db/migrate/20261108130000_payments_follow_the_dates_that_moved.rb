# frozen_string_literal: true

# Moving a contract's date used to leave behind any payment that wasn't linked
# to its show (Full Five Fridays' "Event 10 Fee" sat on Nov 6 after the show
# moved to Nov 20), and left the old date in the names of the ones that did
# move. The move is fixed; ContractPaymentDateRepair puts the leftovers right
# and says what it did.
class PaymentsFollowTheDatesThatMoved < ActiveRecord::Migration[8.1]
  def up
    result = ContractPaymentDateRepair.run!
    result.changes.each { |change| say "#{change.was} => #{change.now}" }
    result.unplaced.each { |line| say "Left alone, nowhere certain to go: #{line}" }
    say "#{result.changes.size} payment(s) repaired, #{result.unplaced.size} left alone"
  end

  def down
    # The old dates were wrong; nothing to put back.
  end
end
