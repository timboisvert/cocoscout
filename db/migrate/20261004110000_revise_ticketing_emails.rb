# frozen_string_literal: true

# The ticketing emails, revised after Tim's review (2026-10-04): buyers get
# a when-and-where block and tickets under short words; the theater's
# notices carry sales tables, products and money, and say "Open this show's
# ticketing" instead of "See the show". The words now live in
# TicketingTemplates; this rewrites what the earlier seeds created.
class ReviseTicketingEmails < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(overwrite: true)
  end

  def down
    # The earlier seed migrations hold the old words; nothing to undo here.
  end
end
