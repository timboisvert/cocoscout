# frozen_string_literal: true

require "bcrypt"

module Dev
  # Makes production's data safe to live in the dev database after
  # bin/seed_dev_from_prod loads it (Tim, 2026-11-01: "I want to copy the
  # people, I don't want to copy all their logins. I want to keep my basic
  # login there." ... "I want to basically seed my dev from prod.").
  #
  # Generic on purpose: it reads the live schema instead of a list of models,
  # so a table added later is covered by the column-name rules below without
  # anyone remembering to update this. spec/services/dev/prod_copy_scrubber_spec.rb
  # fails when a new secret-looking column slips past them.
  #
  # What it does, in one transaction:
  # - keeps the logins named by keep_emails (their dev passwords are put back
  #   afterwards by dev_seed:restore_logins);
  # - every other user: email rewritten to user-<id>@prodcopy.test, password
  #   replaced by one nobody knows;
  # - every other email column: rewritten to <table>-<id>@prodcopy.test, so
  #   nothing in dev can reach a real person (dev mail opens in the browser
  #   anyway); phone columns cleared;
  # - tokens, secrets, provider credentials, payment-provider account,
  #   customer and payment-method ids, and tax ids cleared (or replaced with a
  #   random value where the column can't be empty);
  # - encrypted columns cleared: dev's keys can't read production's;
  # - sessions, device tokens, push apps (Apple and Google credentials) and
  #   their notifications, queued jobs and the cache emptied;
  # - ar_internal_metadata records the day, which the dev indicator shows.
  class ProdCopyScrubber
    SECRET_COLUMN = /\A(?:.*_)?(?:token|token_digest|secret|client_secret|access_token|refresh_token|credentials|api_key|otp_secret)\z|
                     \Astripe_(?:account|customer|subscription|person|bank_account|payment_method|setup_intent)_id\z|
                     (?:\A|_)payment_method_id\z|\Atin(?:_last4)?\z|\Aein\z/x
    EMAIL_COLUMN = /(?:\A|_)(?:email|email_address|emails)\z/
    PHONE_COLUMN = /(?:\A|_)phone(?:_number)?\z/
    EMPTIED_TABLES = %w[sessions device_tokens solid_cache_entries].freeze
    LEFT_ALONE = %w[schema_migrations ar_internal_metadata].freeze

    class Refused < StandardError; end

    def initialize(keep_emails:, copied_on: Date.current, allow_test: false)
      @keep = Array(keep_emails).map { |e| e.to_s.strip.downcase }.compact_blank
      @copied_on = copied_on
      @allow_test = allow_test
      @report = Hash.new(0)
    end

    def run!
      guard!
      conn.transaction do
        empty_tables
        scrub_users
        conn.tables.sort.each { |table| scrub_table(table) }
        clear_encrypted_columns
        mark_copy
      end
      @report
    end

    private

    def conn = ActiveRecord::Base.connection
    def kept_list = @keep.map { |e| conn.quote(e) }.join(", ")

    def guard!
      raise Refused, "no keep_emails: you would lock yourself out" if @keep.empty?
      return if @allow_test && Rails.env.test?

      raise Refused, "only in development" unless Rails.env.development?
    end

    def empty_tables
      tables = EMPTIED_TABLES.select { |t| conn.table_exists?(t) } + conn.tables.grep(/\A(?:solid_queue|rpush)_/)
      return if tables.empty?

      conn.execute("TRUNCATE #{tables.map { |t| conn.quote_table_name(t) }.join(', ')} CASCADE")
      tables.each { |t| @report["emptied #{t}"] = 1 }
    end

    def scrub_users
      return unless conn.table_exists?("users") && conn.column_exists?(:users, :email_address)

      digest = BCrypt::Password.create(SecureRandom.hex(32))
      @report["users locked out"] = conn.update(<<~SQL)
        UPDATE users SET password_digest = #{conn.quote(digest)},
                         email_address = 'user-' || id || '@prodcopy.test'
         WHERE lower(email_address) NOT IN (#{kept_list})
      SQL
    end

    def scrub_table(table)
      return if LEFT_ALONE.include?(table) || EMPTIED_TABLES.include?(table) || table.match?(/\A(?:solid_queue|rpush)_/)

      has_id = conn.columns(table).any? { |c| c.name == "id" }
      conn.columns(table).each do |col|
        next if table == "users" && %w[email_address password_digest].include?(col.name)

        sql = rule_for(table, col, has_id)
        next unless sql

        changed = conn.update("UPDATE #{conn.quote_table_name(table)} SET #{conn.quote_column_name(col.name)} = #{sql} WHERE #{conn.quote_column_name(col.name)} IS NOT NULL")
        @report["#{table}.#{col.name}"] += changed if changed.positive?
      end
    end

    def rule_for(table, col, has_id)
      text = %i[string text].include?(col.type)
      if col.name.match?(SECRET_COLUMN)
        return nil if col.type == :boolean
        return "NULL" if col.null
        return "'0000'" if col.name.end_with?("_last4")
        return "md5(random()::text || clock_timestamp()::text)" if text && !col.array

        return nil
      end
      if text && col.name.match?(EMAIL_COLUMN)
        return (col.null ? "NULL" : "'{}'") if col.array

        keep = "lower(#{conn.quote_column_name(col.name)}) IN (#{kept_list})"
        fake = has_id ? "'#{table}-' || id || '@prodcopy.test'" : "md5(#{conn.quote_column_name(col.name)}) || '@prodcopy.test'"
        return "CASE WHEN #{keep} THEN #{conn.quote_column_name(col.name)} ELSE #{fake} END"
      end
      return (col.null ? "NULL" : "''") if text && !col.array && col.name.match?(PHONE_COLUMN)

      nil
    end

    # Production's encrypted columns can't be read with dev's keys; loading a
    # record that holds one would raise. A column that may be empty is
    # emptied; one that can't be gets a placeholder encrypted with dev's keys.
    PLACEHOLDER = "000000000"

    def clear_encrypted_columns
      # Only the models: the rest of the app isn't needed to find them.
      Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models").to_s)
      ActiveRecord::Base.descendants.each do |model|
        next if model.abstract_class? || !model.table_exists?

        Array(model.try(:encrypted_attributes)).each do |attr|
          column = model.columns_hash[attr.to_s]
          next unless column

          # update_all encrypts through the attribute's type, so the plain
          # placeholder goes in and dev's ciphertext comes out.
          changed = model.unscoped.update_all(attr => column.null ? nil : PLACEHOLDER)
          @report["#{model.table_name}.#{attr} (encrypted)"] += changed if changed.positive?
        end
      end
    end

    def mark_copy
      { "seeded_from_production_on" => @copied_on.iso8601, "seeded_at" => Time.current.iso8601 }.each do |key, value|
        conn.execute(<<~SQL)
          INSERT INTO ar_internal_metadata (key, value, created_at, updated_at)
          VALUES (#{conn.quote(key)}, #{conn.quote(value)}, now(), now())
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()
        SQL
      end
    end
  end
end
