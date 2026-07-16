# frozen_string_literal: true

# Marks a message as in-app only: it still lands in the recipient's inbox (with
# an unread badge) but is never swept into the unread-messages digest email.
# Used for transactional notifications we want delivered as a message, not an
# email — e.g. agreement-signature requests.
class AddSkipDigestToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :skip_digest, :boolean, default: false, null: false
  end
end
