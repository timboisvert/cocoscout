# frozen_string_literal: true

# How much mail CocoScout sends each month, all of it (sign-in, tickets,
# contracts, and email to followers), counted as it goes out (MailVolume),
# so Superadmin can say how close it is to its Mailgun plan. And the words
# of three notices to superadmins: a block of extra follower emails bought,
# the month getting close to the plan, and the pace saying it's time to
# move up a plan.
class CountTheMailCocoscoutSends < ActiveRecord::Migration[8.1]
  def up
    create_table :mail_volume_months do |t|
      t.date :month, null: false
      t.integer :sent, null: false, default: 0
      t.datetime :counted_from
      t.timestamps
    end
    add_index :mail_volume_months, :month, unique: true
    SuperadminTemplates.ensure!
  end

  def down
    drop_table :mail_volume_months
  end
end
