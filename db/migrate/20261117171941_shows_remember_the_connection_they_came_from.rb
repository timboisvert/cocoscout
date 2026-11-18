# frozen_string_literal: true

# A date that followed another organization's contract date, kept as the
# contractor's own after unlinking (LinkedDates.release!), remembers the
# connection it came from: it is marked as no longer following, and the
# coming ones can still be removed together later.
class ShowsRememberTheConnectionTheyCameFrom < ActiveRecord::Migration[8.1]
  def change
    add_reference :shows, :released_connection, foreign_key: { to_table: :contract_connections, on_delete: :nullify }
  end
end
