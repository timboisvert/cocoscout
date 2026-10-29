# frozen_string_literal: true

# Page loads in the apps, per day, platform and page ("controller#action"),
# with no person on them: which screens get used.
class AppPageDay < ApplicationRecord
  # One more load of this page today, in one statement.
  def self.count!(page, platform:, day: Date.current)
    sql = sanitize_sql_array([ <<~SQL.squish, day, platform, page.to_s.first(120) ])
      INSERT INTO app_page_days (day, platform, page, views) VALUES (?, ?, ?, 1)
      ON CONFLICT (day, platform, page) DO UPDATE SET views = app_page_days.views + 1
    SQL
    connection.execute(sql)
  end
end
