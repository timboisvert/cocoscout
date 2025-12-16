# frozen_string_literal: true

class RenameAuditionRequestStatusValues < ActiveRecord::Migration[8.1]
  def up
    # Rename status enum values:
    # unreviewed (0) -> pending (0)
    # undecided (1) -> pending (0) - merge into pending
    # passed (2) -> rejected (2)
    # accepted (3) -> approved (1)

    # First, convert undecided (1) to pending (0)
    execute "UPDATE audition_requests SET status = 0 WHERE status = 1"

    # Then, convert accepted (3) to approved - we'll use value 1
    execute "UPDATE audition_requests SET status = 1 WHERE status = 3"

    # passed (2) stays as rejected (2)
    # No change needed for value 2
  end

  def down
    # Reverse the changes
    # approved (1) -> accepted (3)
    execute "UPDATE audition_requests SET status = 3 WHERE status = 1"

    # pending (0) stays as unreviewed (0)
    # No change needed

    # rejected (2) stays as passed (2)
    # No change needed
  end
end
