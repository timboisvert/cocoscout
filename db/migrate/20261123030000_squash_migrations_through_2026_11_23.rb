# frozen_string_literal: true

# The 918 migrations from the start of CocoScout through 2026-11-22 (every one
# production had run) were squashed into db/schema.rb; it was on the to-do
# list for after 1.4 merged. Their versions are listed in
# db/squashed_migrations.txt. The five that specs load to check what they did
# live on in spec/fixtures/migrations. 20261123020000 hadn't reached
# production yet, so it stays a migration of its own and runs before this.
#
# A new database loads db/schema.rb (bin/rails db:prepare, as CI and new
# servers do), which records this migration as run without running it.
#
# An existing database (production, a copy of it) must already have run every
# squashed migration. This checks that once and changes nothing. If one is
# missing, it stops: migrate that database with the code from before the
# squash first, so nothing it needed is skipped.
class SquashMigrationsThrough20261123 < ActiveRecord::Migration[8.1]
  def up
    unless table_exists?(:users)
      raise ActiveRecord::IrreversibleMigration,
            "This database is empty. Build it from db/schema.rb with bin/rails db:prepare, not by migrating."
    end

    squashed = Rails.root.join("db/squashed_migrations.txt").read.split
    ran = select_values("SELECT version FROM schema_migrations")
    missing = squashed - ran
    return if missing.empty?

    raise "#{missing.size} squashed migration(s) never ran on this database (#{missing.first(5).join(', ')}" \
          "#{', ...' if missing.size > 5}). Migrate it with the code from before the squash, then again with this."
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
