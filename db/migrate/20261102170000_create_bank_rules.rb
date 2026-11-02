# frozen_string_literal: true

# Bank rules (Books V1.3, plan D3; Tim, 2026-11-02): "if the bank's
# description has RESTAURANT DEPOT in it, that's bar purchases from
# Restaurant Depot" and "SQUARE INC paying us is bar sales". A rule records
# or ignores every line it fits, the ones waiting now and the ones in
# statements brought in later. And the notification for a run of rules
# that went to the background.
class CreateBankRules < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    create_table :bank_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :contains, null: false
      t.string :direction, null: false, default: "any"
      t.string :action, null: false, default: "record"
      t.string :category_key
      t.string :counterparty
      t.references :production, foreign_key: true
      t.boolean :on_import, null: false, default: true
      t.integer :applied_count, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    t = Template.find_or_initialize_by(key: "bank_rules_applied")
    t.assign_attributes(
      name: "Bank rules applied",
      subject: "Your bank rules dealt with {{dealt_with}} lines; {{to_deal_with}} left",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>Your bank rules for {{organization_name}} went through the lines waiting on Books → Bank: {{recorded}} recorded on the books " \
            "and {{ignored}} ignored. {{to_deal_with}} are left to deal with.</p>" \
            "<p><a href=\"{{bank_url}}\">Open Books → Bank</a>.</p>",
      category: "books",
      channel: "message",
      active: true,
      available_variables: %w[recipient_name organization_name dealt_with recorded ignored to_deal_with bank_url]
    )
    t.save!
  end

  def down
    Template.where(key: "bank_rules_applied").delete_all
    drop_table :bank_rules
  end
end
