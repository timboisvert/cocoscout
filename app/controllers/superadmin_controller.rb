# frozen_string_literal: true

class SuperadminController < ApplicationController
  before_action :require_superadmin,
                only: %i[index impersonate change_email queue queue_failed queue_retry queue_delete_job queue_clear_failed
                         queue_clear_pending people_list person_detail destroy_person organizations_list organization_detail]
  before_action :hide_sidebar

  def hide_sidebar
    @show_my_sidebar = false
  end

  def index
    @users = User.order(:email_address)

    # Organization stats for overview
    # People stats for overview
    @people_total = Person.count
    @people_new_this_week = Person.where("created_at > ?", 1.week.ago).count
    @people_new_this_month = Person.where("created_at > ?", 1.month.ago).count
    @recent_people = Person.order(created_at: :desc).limit(5)

    # Organization stats for overview
    @organizations_total = Organization.count
    @organizations_new_this_week = Organization.where("created_at > ?", 1.week.ago).count
    @organizations_new_this_month = Organization.where("created_at > ?", 1.month.ago).count
    @recent_organizations = Organization.order(created_at: :desc).limit(5)

    if cookies.encrypted[:recent_impersonations].present?
      begin
        @recent_impersonations = JSON.parse(cookies.encrypted[:recent_impersonations])
      rescue JSON::ParserError
        @recent_impersonations = []
      end
    else
      @recent_impersonations = []
    end
  end

  def people_list
    @search = params[:search].to_s.strip
    @filter = params[:filter].to_s.strip
    @people = Person.includes(:user).order(created_at: :desc)

    # Apply filter for suspicious people
    @people = @people.suspicious if @filter == "suspicious"

    # Filter by search term if provided (search by name or email)
    if @search.present?
      search_term = "%#{@search}%"
      @people = @people.where("name LIKE ? OR email LIKE ?", search_term, search_term)
    end

    @pagy, @people = pagy(@people, items: 25)
    @suspicious_count = Person.suspicious.count
  end

  def person_detail
    @person = Person.find(params[:id])
  end

  def destroy_person
    @person = Person.find(params[:id])
    person_name = @person.name

    destroy_person_record(@person)

    redirect_to people_list_path, notice: "#{person_name} was successfully deleted", status: :see_other
  end

  def bulk_destroy_people
    person_ids = params[:person_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if person_ids.empty?
      redirect_to people_list_path, alert: "No people selected for deletion", status: :see_other
      return
    end

    people = Person.where(id: person_ids)
    count = people.count

    ActiveRecord::Base.transaction do
      people.find_each do |person|
        destroy_person_record(person)
      end
    end

    redirect_to people_list_path(filter: params[:filter], search: params[:search]),
                notice: "Successfully deleted #{count} #{'person'.pluralize(count)}",
                status: :see_other
  end

  def destroy_all_suspicious_people
    people = Person.suspicious
    count = people.count

    if count.zero?
      redirect_to people_list_path, alert: "No suspicious people to delete", status: :see_other
      return
    end

    ActiveRecord::Base.transaction do
      people.find_each do |person|
        destroy_person_record(person)
      end
    end

    redirect_to people_list_path, notice: "Successfully deleted all #{count} suspicious #{'person'.pluralize(count)}",
                                  status: :see_other
  end

  def organizations_list
    @search = params[:search].to_s.strip
    @organizations = Organization.includes(owner: :default_person).order(created_at: :desc)

    # Filter by search term if provided (search by org name or owner email/name)
    if @search.present?
      search_term = "%#{@search}%"
      @organizations = @organizations.joins(:owner)
                                     .where("organizations.name LIKE ? OR users.email_address LIKE ? OR people.name LIKE ?",
                                            search_term, search_term, search_term)
                                     .joins("LEFT JOIN people ON users.person_id = people.id")
                                     .distinct
    end

    @pagy, @organizations = pagy(@organizations, items: 25)
  end

  def organization_detail
    @organization = Organization.find(params[:id])
  end

  def impersonate
    # Store the current user
    session[:user_doing_the_impersonating] = Current.user.id

    # Get the user being impersonated
    user = User.find_by(email_address: params[:email].to_s.strip.downcase)
    if user
      # Update recent impersonations cookie (store email and name)
      recent = []
      if cookies.encrypted[:recent_impersonations].present?
        begin
          recent = JSON.parse(cookies.encrypted[:recent_impersonations])
        rescue JSON::ParserError
          recent = []
        end
      end
      # Remove if already present, then unshift new record
      recent.reject! { |e| e["email"] == user.email_address }
      recent.unshift({ "email" => user.email_address, "name" => user.person&.name || user.email_address })
      # Keep only the 5 most recent
      recent = recent.first(5)
      cookies.encrypted[:recent_impersonations] = {
        value: JSON.generate(recent),
        expires: 30.days.from_now,
        httponly: true
      }

      # End any current session and impersonation
      terminate_session

      # Set the impersonating id and start a new session
      session[:impersonate_user_id] = user.id
      start_new_session_for user
    end

    # Redirect
    redirect_to my_dashboard_path and return
  end

  def stop_impersonating
    # Kill the impersonation session
    terminate_session
    session.delete(:impersonate_user_id)

    # Restore the original user
    if session[:user_doing_the_impersonating]
      original_user = User.find_by(id: session[:user_doing_the_impersonating])
      start_new_session_for original_user if original_user
    end

    session.delete(:user_doing_the_impersonating)
    redirect_to my_dashboard_path
  end

  def change_email
    old_email = params[:old_email].to_s.strip.downcase
    new_email = params[:new_email].to_s.strip.downcase

    # Find user and person with old email
    user = User.find_by(email_address: old_email)
    person = Person.find_by(email: old_email)

    if user.nil?
      redirect_to superadmin_path, alert: "No user found with email: #{old_email}"
      return
    end

    # Check if new email is already taken
    if User.exists?(email_address: new_email)
      redirect_to superadmin_path, alert: "A user with email #{new_email} already exists"
      return
    end

    # Wrap in a transaction so both updates succeed or both are rolled back
    updates_made = []
    ActiveRecord::Base.transaction do
      # Update user email
      user.update!(email_address: new_email)
      updates_made << "User email"

      # Update person email if person exists
      if person
        person.update!(email: new_email)
        updates_made << "Person email"

        # If person has no production companies, note that
        updates_made << "(Note: Person has no production company associations)" if person.organizations.empty?
      end
    end

    redirect_to superadmin_path,
                notice: "Successfully changed email from #{old_email} to #{new_email}. Updated: #{updates_made.join(', ')}"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to superadmin_path, alert: "Failed to change email: #{e.message}"
  end

  def email_logs
    # Exclude the heavy 'body' column from list queries for performance
    @email_logs = EmailLog
                  .select(:id, :user_id, :recipient, :subject, :mailer_class, :mailer_action,
                          :message_id, :delivery_status, :sent_at, :delivered_at, :error_message,
                          :created_at, :updated_at)
                  .includes(:user)
                  .order(sent_at: :desc)
                  .limit(100)

    # Filter by user if requested
    @email_logs = @email_logs.where(user_id: params[:user_id]) if params[:user_id].present?

    # Filter by recipient if requested
    return unless params[:recipient].present?

    @email_logs = @email_logs.where("recipient LIKE ?", "%#{params[:recipient]}%")
  end

  def email_log
    @email_log = EmailLog.find(params[:id])
  end

  def queue
    # Get overall stats
    @total_jobs = SolidQueue::Job.count
    @pending_jobs = SolidQueue::Job.where(finished_at: nil).count
    @finished_today = SolidQueue::Job.where(finished_at: Time.current.beginning_of_day..Time.current).count
    @failed_jobs = SolidQueue::FailedExecution.count
    @active_workers = SolidQueue::Process.where("last_heartbeat_at > ?", 5.minutes.ago).count

    # Recent jobs (last 50)
    @recent_jobs = SolidQueue::Job
                   .order(created_at: :desc)
                   .limit(50)
                   .select(:id, :queue_name, :class_name, :created_at, :finished_at, :scheduled_at)

    # Queue breakdown
    @queue_stats = SolidQueue::Job
                   .where(finished_at: nil)
                   .group(:queue_name)
                   .count
                   .sort_by { |_, count| -count }
  rescue ActiveRecord::StatementInvalid
    # Queue database not accessible
    @total_jobs = 0
    @pending_jobs = 0
    @finished_today = 0
    @failed_jobs = 0
    @active_workers = 0
    @recent_jobs = []
    @queue_stats = {}
    flash.now[:alert] = "Queue database not accessible. This is normal in development."
  end

  def queue_failed
    @failed_executions = SolidQueue::FailedExecution
                         .joins(:job)
                         .includes(:job)
                         .order(Arel.sql("solid_queue_failed_executions.created_at DESC"))
                         .limit(100)
                         .select("solid_queue_failed_executions.*, solid_queue_jobs.*")
  end

  def queue_retry
    failed_execution = SolidQueue::FailedExecution.find(params[:id])

    # Use SolidQueue's built-in retry mechanism
    failed_execution.retry

    redirect_to queue_failed_path, notice: "Job queued for retry"
  rescue StandardError => e
    redirect_to queue_failed_path, alert: "Failed to retry job: #{e.message}"
  end

  def queue_retry_all_failed
    failed_executions = SolidQueue::FailedExecution.includes(:job).all
    retry_count = 0
    error_count = 0

    failed_executions.each do |failed_execution|
      begin
        # Use SolidQueue's built-in retry mechanism
        failed_execution.retry
        retry_count += 1
      rescue StandardError => e
        Rails.logger.error "Failed to retry job #{failed_execution.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_count += 1
      end
    end

    if error_count.zero?
      redirect_to queue_monitor_path, notice: "Successfully queued #{retry_count} failed job(s) for retry"
    else
      redirect_to queue_monitor_path, alert: "Queued #{retry_count} job(s) for retry, #{error_count} failed. Check logs for details."
    end
  end

  def queue_delete_job
    job = SolidQueue::Job.find(params[:id])
    job.destroy
    redirect_to queue_monitor_path, notice: "Job deleted"
  rescue StandardError => e
    redirect_to queue_monitor_path, alert: "Failed to delete job: #{e.message}"
  end

  def queue_clear_failed
    count = SolidQueue::FailedExecution.count
    SolidQueue::FailedExecution.destroy_all
    redirect_to queue_monitor_path, notice: "Cleared #{count} failed jobs"
  rescue StandardError => e
    redirect_to queue_monitor_path, alert: "Failed to clear failed jobs: #{e.message}"
  end

  def queue_clear_pending
    count = SolidQueue::Job.where(finished_at: nil).count
    SolidQueue::Job.where(finished_at: nil).destroy_all
    redirect_to queue_monitor_path, notice: "Cleared #{count} pending jobs"
  rescue StandardError => e
    redirect_to queue_monitor_path, alert: "Failed to clear pending jobs: #{e.message}"
  end

  def storage
    # Overall stats
    @total_blobs = ActiveStorage::Blob.count
    @total_size_bytes = ActiveStorage::Blob.sum(:byte_size)

    # By service
    @blobs_by_service = ActiveStorage::Blob.group(:service_name).count
    @size_by_service = ActiveStorage::Blob.group(:service_name).sum(:byte_size)

    # By content type
    @blobs_by_content_type = ActiveStorage::Blob.group(:content_type).count.sort_by { |_, v| -v }

    # Attachments breakdown
    @attachments_by_type = ActiveStorage::Attachment.group(:record_type, :name).count.sort_by { |_, v| -v }

    # Orphaned blobs
    @orphaned_blobs = ActiveStorage::Blob.left_joins(:attachments)
                                         .where(active_storage_attachments: { id: nil })
    @orphaned_count = @orphaned_blobs.count
    @orphaned_size = @orphaned_blobs.sum(:byte_size)
    @orphaned_by_service = @orphaned_blobs.group(:service_name).count

    # Legacy Person attachments
    @legacy_attachments = ActiveStorage::Attachment.where(record_type: "Person", name: %w[headshot resume])
    @legacy_count = @legacy_attachments.count

    # Key structure analysis - exclude variant records and preview images
    # which are internal Active Storage derivatives that use flat keys by design
    variant_blob_ids = ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord").pluck(:blob_id)
    preview_blob_ids = ActiveStorage::Attachment.where(record_type: "ActiveStorage::Blob", name: "preview_image").pluck(:blob_id)
    excluded_blob_ids = variant_blob_ids + preview_blob_ids

    flat_keys_query = ActiveStorage::Blob.where("key NOT LIKE '%/%'")
    flat_keys_query = flat_keys_query.where.not(id: excluded_blob_ids) if excluded_blob_ids.any?

    @flat_keys_count = flat_keys_query.count
    @hierarchical_keys_count = ActiveStorage::Blob.where("key LIKE '%/%'").count
    @flat_keys_by_service = flat_keys_query.group(:service_name).count

    # Variant records
    @variant_count = ActiveStorage::VariantRecord.count
  end

  def storage_cleanup_orphans
    orphaned = ActiveStorage::Blob.left_joins(:attachments)
                                  .where(active_storage_attachments: { id: nil })
    count = orphaned.count

    if params[:service].present?
      orphaned = orphaned.where(service_name: params[:service])
      count = orphaned.count
    end

    orphaned.find_each(&:purge)
    redirect_to storage_monitor_path, notice: "Purged #{count} orphaned blobs"
  rescue StandardError => e
    redirect_to storage_monitor_path, alert: "Failed to cleanup orphans: #{e.message}"
  end

  def storage_cleanup_legacy
    legacy = ActiveStorage::Attachment.where(record_type: "Person", name: %w[headshot resume])
    count = legacy.count
    legacy.delete_all
    redirect_to storage_monitor_path, notice: "Deleted #{count} legacy Person attachments"
  rescue StandardError => e
    redirect_to storage_monitor_path, alert: "Failed to cleanup legacy attachments: #{e.message}"
  end

  def storage_migrate_keys
    # Auto-detect service with flat keys if not specified
    service_name = params[:service].presence
    service_name ||= ActiveStorage::Blob
                     .where("key NOT LIKE '%/%'")
                     .group(:service_name)
                     .count
                     .max_by { |_, count| count }
                     &.first

    unless service_name
      redirect_to storage_monitor_path, notice: "No flat keys to migrate"
      return
    end

    migrated = 0
    errors = []
    limit = params[:limit].to_i if params[:limit].present?

    # Only migrate blobs with flat keys (no /)
    blobs_query = ActiveStorage::Blob
                  .where(service_name: service_name)
                  .where("key NOT LIKE '%/%'")
                  .joins(:attachments)
                  .includes(:attachments)
                  .distinct

    # Apply limit if specified (for testing migration with a small batch)
    blobs_to_migrate = limit ? blobs_query.limit(limit) : blobs_query

    # Get the storage service
    storage_service = ActiveStorage::Blob.services.fetch(service_name.to_sym)

    blobs_to_migrate.each do |blob|
      new_key = StorageKeyGeneratorService.generate_key_for_blob(blob)
      next if new_key.nil? || new_key == blob.key

      # Copy object to new key using S3 client directly
      if storage_service.respond_to?(:bucket)
        # S3 service - use copy_object
        storage_service.bucket.object(new_key).copy_from(
          copy_source: "#{storage_service.bucket.name}/#{blob.key}"
        )
      else
        # Disk service - download and re-upload
        data = blob.download
        storage_service.upload(new_key, StringIO.new(data), checksum: blob.checksum)
      end

      # Update the blob record
      blob.key
      blob.update_column(:key, new_key)

      # NOTE: Old key is preserved. Run delete_old_keys after verifying migration.

      migrated += 1
    rescue StandardError => e
      errors << "Blob #{blob.id}: #{e.message}"
    end

    message = "Migrated #{migrated} blobs to hierarchical keys"
    message += ". Errors: #{errors.first(3).join('; ')}" if errors.any?

    redirect_to storage_monitor_path, notice: message
  rescue StandardError => e
    redirect_to storage_monitor_path, alert: "Migration failed: #{e.message}"
  end

  def storage_cleanup_s3_orphans
    # This finds files on S3 that don't have a corresponding blob record
    # WARNING: This is a slow operation as it lists all S3 objects

    storage_service = ActiveStorage::Blob.services.fetch(:amazon)

    unless storage_service.respond_to?(:bucket)
      redirect_to storage_monitor_path, alert: "S3 cleanup only works with Amazon S3 service"
      return
    end

    # Get all blob keys from the database
    db_keys = Set.new(ActiveStorage::Blob.where(service_name: "amazon").pluck(:key))

    # Also include variant keys (they're stored differently)
    # Variants use the format: variants/{blob_key}/{variant_key}

    deleted_count = 0
    deleted_size = 0
    errors = []

    # List all objects in the bucket and delete orphans
    storage_service.bucket.objects.each do |object|
      key = object.key

      # Skip if this key exists in the database
      next if db_keys.include?(key)

      # Skip variant files - they reference the parent blob key
      # Format: variants/{blob_key}/{variant_key}
      if key.start_with?("variants/")
        parent_key = key.split("/")[1]
        next if db_keys.include?(parent_key)
      end

      begin
        deleted_size += object.size
        object.delete
        deleted_count += 1
      rescue StandardError => e
        errors << "#{key}: #{e.message}"
      end
    end

    message = "Deleted #{deleted_count} orphaned S3 files (#{ActionController::Base.helpers.number_to_human_size(deleted_size)})"
    message += ". Errors: #{errors.first(3).join('; ')}" if errors.any?

    redirect_to storage_monitor_path, notice: message
  rescue StandardError => e
    redirect_to storage_monitor_path, alert: "S3 cleanup failed: #{e.message}"
  end

  # Data Monitor - Database table statistics
  def data
    # Get list of all ActiveRecord models
    @tables = []

    # Get all tables from the database
    table_names = ActiveRecord::Base.connection.tables.sort

    # Detect database adapter
    adapter = ActiveRecord::Base.connection.adapter_name.downcase

    # Calculate table sizes based on database type
    table_sizes = {}
    if adapter.include?("postgresql")
      # PostgreSQL: use pg_catalog tables for accurate size info
      begin
        results = ActiveRecord::Base.connection.execute(<<~SQL)
          SELECT
            relname as name,
            pg_total_relation_size(quote_ident(relname)) as size_bytes
          FROM pg_catalog.pg_stat_user_tables
          ORDER BY pg_total_relation_size(quote_ident(relname)) DESC
        SQL
        results.each do |row|
          table_sizes[row["name"]] = row["size_bytes"].to_i
        end
      rescue StandardError => e
        Rails.logger.warn "Could not query pg_catalog: #{e.message}"
      end
    else
      # SQLite: use dbstat virtual table
      begin
        results = ActiveRecord::Base.connection.execute(
          "SELECT name, SUM(pgsize) as size_bytes FROM dbstat GROUP BY name"
        )
        results.each do |row|
          table_sizes[row["name"]] = row["size_bytes"].to_i
        end
      rescue StandardError => e
        Rails.logger.warn "Could not query dbstat: #{e.message}"
      end
    end

    # Get database bloat/vacuum info based on adapter
    @freelist_count = 0
    @page_count = 0
    @freelist_bytes = 0
    @freelist_percent = 0
    @bloat_info = nil

    if adapter.include?("postgresql")
      # PostgreSQL: check for table bloat using pg_stat_user_tables
      begin
        result = ActiveRecord::Base.connection.execute(<<~SQL)
          SELECT
            SUM(pg_total_relation_size(quote_ident(relname))) as total_size,
            SUM(n_dead_tup) as dead_tuples,
            SUM(n_live_tup) as live_tuples
          FROM pg_catalog.pg_stat_user_tables
        SQL
        row = result.first
        if row
          dead_tuples = row["dead_tuples"].to_i
          live_tuples = row["live_tuples"].to_i
          total_tuples = dead_tuples + live_tuples
          if total_tuples > 0 && dead_tuples > 1000
            @freelist_percent = (dead_tuples.to_f / total_tuples * 100).round(1)
            @bloat_info = { dead_tuples: dead_tuples, live_tuples: live_tuples }
          end
        end
      rescue StandardError => e
        Rails.logger.warn "Could not query PostgreSQL bloat: #{e.message}"
      end
    else
      # SQLite: check freelist for vacuum recommendation
      begin
        @page_count = ActiveRecord::Base.connection.execute("PRAGMA page_count").first.values.first.to_i
        @freelist_count = ActiveRecord::Base.connection.execute("PRAGMA freelist_count").first.values.first.to_i
        page_size = ActiveRecord::Base.connection.execute("PRAGMA page_size").first.values.first.to_i
        @freelist_bytes = @freelist_count * page_size
        @freelist_percent = @page_count > 0 ? (@freelist_count.to_f / @page_count * 100).round(1) : 0
      rescue StandardError
        # Ignore
      end
    end

    table_names.each do |table_name|
      # Skip internal Rails tables
      next if %w[schema_migrations ar_internal_metadata].include?(table_name)

      table_info = {
        name: table_name,
        row_count: 0,
        size_bytes: table_sizes[table_name],
        model_name: nil,
        recent_count: 0,
        oldest_at: nil,
        newest_at: nil
      }

      # Get row count
      begin
        table_info[:row_count] = ActiveRecord::Base.connection.execute(
          "SELECT COUNT(*) FROM #{table_name}"
        ).first.values.first
      rescue StandardError
        table_info[:row_count] = 0
      end

      # Try to find the corresponding model
      begin
        model_name = table_name.classify
        model = model_name.safe_constantize
        if model && model < ApplicationRecord
          table_info[:model_name] = model_name

          # Get timestamps if available
          if model.column_names.include?("created_at")
            table_info[:oldest_at] = model.minimum(:created_at)
            table_info[:newest_at] = model.maximum(:created_at)
            table_info[:recent_count] = model.where("created_at > ?", 7.days.ago).count
          end
        end
      rescue StandardError
        # Model not found or not accessible
      end

      @tables << table_info
    end

    # Sort by size descending (fall back to row count if no size)
    @tables.sort_by! { |t| -(t[:size_bytes] || 0) }

    # Calculate total table size
    @total_table_size = @tables.sum { |t| t[:size_bytes] || 0 }

    # Summary statistics
    @total_tables = @tables.count
    @total_rows = @tables.sum { |t| t[:row_count] }

    # Database file sizes - approach differs by adapter
    @database_files = []
    @total_db_size = 0

    if adapter.include?("postgresql")
      # PostgreSQL: get database size from pg_database
      begin
        result = ActiveRecord::Base.connection.execute(<<~SQL)
          SELECT
            pg_database.datname as name,
            pg_database_size(pg_database.datname) as size_bytes
          FROM pg_database
          WHERE datname = current_database()
        SQL
        row = result.first
        if row
          @total_db_size = row["size_bytes"].to_i
          @database_files << {
            name: row["name"],
            path: "PostgreSQL/",
            size_bytes: row["size_bytes"].to_i,
            modified_at: Time.current
          }
        end
      rescue StandardError => e
        Rails.logger.warn "Could not query PostgreSQL database size: #{e.message}"
      end
    else
      # SQLite: scan for database files on disk
      # Main database files
      db_path = Rails.root.join("db")
      Dir.glob(db_path.join("*.sqlite3*")).each do |file_path|
        next unless File.exist?(file_path)

        file_size = File.size(file_path)
        @total_db_size += file_size
        @database_files << {
          name: File.basename(file_path),
          path: "db/",
          size_bytes: file_size,
          modified_at: File.mtime(file_path)
        }
      end

      # Storage folder databases
      storage_path = Rails.root.join("storage")
      Dir.glob(storage_path.join("*.sqlite3*")).each do |file_path|
        next unless File.exist?(file_path)

        file_size = File.size(file_path)
        @total_db_size += file_size
        @database_files << {
          name: File.basename(file_path),
          path: "storage/",
          size_bytes: file_size,
          modified_at: File.mtime(file_path)
        }
      end
    end

    # Sort database files by size descending
    @database_files.sort_by! { |f| -f[:size_bytes] }

    # Index information
    @indexes = []
    table_names.each do |table_name|
      next if %w[schema_migrations ar_internal_metadata].include?(table_name)

      begin
        indexes = ActiveRecord::Base.connection.indexes(table_name)
        indexes.each do |index|
          @indexes << {
            table: table_name,
            name: index.name,
            columns: index.columns,
            unique: index.unique
          }
        end
      rescue StandardError
        # Skip if can't get indexes
      end
    end

    # Storage breakdown - show where the space is actually going
    @storage_breakdown = []

    # Active Storage blobs (the big one!)
    begin
      if defined?(ActiveStorage::Blob)
        blob_size = ActiveStorage::Blob.sum(:byte_size)
        blob_count = ActiveStorage::Blob.count
        @storage_breakdown << {
          name: "Active Storage Blobs",
          size_bytes: blob_size,
          count: blob_count,
          unit: "files",
          color: "bg-pink-500",
          description: "Uploaded images, videos, and files (headshots, reels, attachments)"
        }
      end
    rescue StandardError
      # Skip if Active Storage not available
    end

    # Calculate storage folder size (actual files on disk)
    storage_folder_path = Rails.root.join("storage")
    @active_storage_files_on_disk = 0
    @active_storage_blob_count = 0
    if storage_folder_path.exist?
      # Sum all files in storage subdirectories (exclude .sqlite3 files)
      Dir.glob(storage_folder_path.join("**/*")).each do |file_path|
        next unless File.file?(file_path)
        next if file_path.end_with?(".sqlite3", ".sqlite3-shm", ".sqlite3-wal")

        @active_storage_files_on_disk += File.size(file_path)
        @active_storage_blob_count += 1
      end
    end

    # Main development.sqlite3 data tables
    main_db_size = @database_files.find { |f| f[:name] == "development.sqlite3" }&.dig(:size_bytes) || 0
    @storage_breakdown << {
      name: "Application Data",
      size_bytes: main_db_size,
      count: @total_rows,
      unit: "rows",
      color: "bg-blue-500",
      description: "Core application tables (users, profiles, organizations, etc.)"
    }

    # Solid Queue database
    queue_size = @database_files.select { |f| f[:name].include?("queue") }.sum { |f| f[:size_bytes] }
    if queue_size > 0
      queue_jobs = 0
      begin
        queue_jobs = SolidQueue::Job.count if defined?(SolidQueue::Job)
      rescue StandardError
        # Skip
      end
      @storage_breakdown << {
        name: "Background Jobs Queue",
        size_bytes: queue_size,
        count: queue_jobs,
        unit: "jobs",
        color: "bg-purple-500",
        description: "Solid Queue job storage and history"
      }
    end

    # Cache database
    cache_size = @database_files.select { |f| f[:name].include?("cache") }.sum { |f| f[:size_bytes] }
    if cache_size > 0
      cache_entries = 0
      begin
        cache_entries = SolidCache::Entry.count if defined?(SolidCache::Entry)
      rescue StandardError
        # Skip
      end
      @storage_breakdown << {
        name: "Cache Storage",
        size_bytes: cache_size,
        count: cache_entries,
        unit: "entries",
        color: "bg-green-500",
        description: "Solid Cache key-value storage"
      }
    end

    # Sort by size descending
    @storage_breakdown.sort_by! { |item| -item[:size_bytes] }
  end

  # Cache Monitor
  def cache
    if solid_cache_available?
      @entry_count = SolidCache::Entry.count
      @total_bytes = SolidCache::Entry.sum(:byte_size)
      @max_size = 256.megabytes
      @usage_percent = @max_size.positive? ? (@total_bytes.to_f / @max_size * 100).round(1) : 0

      @oldest_entry = SolidCache::Entry.minimum(:created_at)
      @newest_entry = SolidCache::Entry.maximum(:created_at)

      # Size distribution
      @size_distribution = calculate_size_distribution

      # Key patterns analysis
      @key_patterns = analyze_key_patterns

      # Recent entries
      @recent_entries = SolidCache::Entry
                        .order(created_at: :desc)
                        .limit(20)
                        .pluck(:key, :byte_size, :created_at)
                        .map { |k, s, t| { key: decode_key(k), size: s, created_at: t } }

      # Cache health
      @cache_healthy = test_cache_connectivity
    else
      @solid_cache_available = false
    end
  end

  def cache_clear
    count_before = solid_cache_available? ? SolidCache::Entry.count : 0

    Rails.cache.clear

    count_after = solid_cache_available? ? SolidCache::Entry.count : 0
    cleared = count_before - count_after

    redirect_to cache_monitor_path, notice: "Cache cleared. #{cleared} entries removed."
  rescue StandardError => e
    redirect_to cache_monitor_path, alert: "Cache clear failed: #{e.message}"
  end

  def cache_clear_pattern
    pattern = params[:pattern].to_s.strip
    return redirect_to cache_monitor_path, alert: "Pattern is required" if pattern.blank?

    # Since Solid Cache doesn't support delete_matched, we manually find and delete matching entries
    if solid_cache_available?
      matching = SolidCache::Entry.where("key LIKE ?", "%#{pattern}%")
      count = matching.count
      matching.delete_all

      redirect_to cache_monitor_path, notice: "Cleared #{count} cache entries matching '#{pattern}'"
    else
      redirect_to cache_monitor_path, alert: "Pattern clearing requires Solid Cache"
    end
  rescue StandardError => e
    redirect_to cache_monitor_path, alert: "Pattern clear failed: #{e.message}"
  end

  private

  def require_superadmin
    return if Current.user&.superadmin?

    redirect_to my_dashboard_path
  end

  # Cache helper methods
  def solid_cache_available?
    defined?(SolidCache::Entry) && SolidCache::Entry.table_exists?
  rescue StandardError
    false
  end

  def calculate_size_distribution
    return {} unless solid_cache_available?

    ranges = {
      "< 1 KB" => SolidCache::Entry.where("byte_size < ?", 1.kilobyte).count,
      "1-10 KB" => SolidCache::Entry.where("byte_size >= ? AND byte_size < ?", 1.kilobyte, 10.kilobytes).count,
      "10-100 KB" => SolidCache::Entry.where("byte_size >= ? AND byte_size < ?", 10.kilobytes, 100.kilobytes).count,
      "100 KB - 1 MB" => SolidCache::Entry.where("byte_size >= ? AND byte_size < ?", 100.kilobytes, 1.megabyte).count,
      "> 1 MB" => SolidCache::Entry.where("byte_size >= ?", 1.megabyte).count
    }
    ranges.reject { |_, v| v.zero? }
  end

  def analyze_key_patterns
    return [] unless solid_cache_available?

    entries = SolidCache::Entry.limit(500).pluck(:key, :byte_size)
    patterns = Hash.new { |h, k| h[k] = { count: 0, bytes: 0 } }

    entries.each do |key_binary, byte_size|
      key = decode_key(key_binary)
      pattern = extract_key_pattern(key)
      patterns[pattern][:count] += 1
      patterns[pattern][:bytes] += byte_size
    end

    patterns.sort_by { |_, v| -v[:count] }.first(10)
  end

  def extract_key_pattern(key)
    # Remove specific IDs/timestamps to find the pattern
    # Examples: "person_card_v1/123/1234567890" -> "person_card_v1"
    #           "views/manage/..." -> "views/manage"
    key.to_s.split("/").first(2).join("/").truncate(50)
  rescue StandardError
    "unknown"
  end

  def decode_key(key_binary)
    key_binary.to_s.force_encoding("UTF-8")
  rescue StandardError
    key_binary.to_s
  end

  def test_cache_connectivity
    test_key = "superadmin_cache_test_#{Time.current.to_i}"
    Rails.cache.write(test_key, "ok", expires_in: 1.minute)
    result = Rails.cache.read(test_key) == "ok"
    Rails.cache.delete(test_key)
    result
  rescue StandardError
    false
  end

  def destroy_person_record(person)
    user = person.user

    # Clear join tables - explicitly destroy memberships for proper polymorphic cleanup
    person.talent_pool_memberships.destroy_all
    person.organizations.clear

    # Clear any direct person_id references in show_person_role_assignments
    # (legacy column alongside polymorphic assignable_id/assignable_type)
    ShowPersonRoleAssignment.where(person_id: person.id).update_all(person_id: nil)

    # Nullify person's user_id before destroying user (foreign key constraint)
    if user
      person.update_column(:user_id, nil)
      user.destroy!
    end

    # Now destroy the person (dependent associations will be handled automatically)
    person.destroy!
  end

  # Safely constantize job class names - only allows ApplicationJob subclasses
  def safe_constantize_job(class_name)
    return nil if class_name.blank?

    # Try to constantize and verify it's a valid job class
    klass = class_name.safe_constantize
    return nil unless klass

    # Ensure it's an ApplicationJob subclass (ActiveJob::Base for Rails jobs)
    klass if klass < ApplicationJob || klass < ActiveJob::Base
  rescue NameError
    nil
  end
end
