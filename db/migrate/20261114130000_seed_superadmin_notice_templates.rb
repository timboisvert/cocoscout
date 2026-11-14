# frozen_string_literal: true

# The words of the superadmins' notifications about the business, added on
# 2026-11-14 (SuperadminTemplates): a new organization, and an organization
# starting to pay for Pro.
class SeedSuperadminNoticeTemplates < ActiveRecord::Migration[8.1]
  def up
    SuperadminTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: SuperadminTemplates::TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
