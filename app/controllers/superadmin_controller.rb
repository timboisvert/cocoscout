class SuperadminController < ApplicationController
  before_action :require_superadmin, only: [ :index, :impersonate, :change_email, :queue, :queue_failed, :queue_retry, :queue_delete_job, :queue_clear_failed, :queue_clear_pending, :people_list, :person_detail, :destroy_person, :organizations_list, :organization_detail ]
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
    @people = Person.order(created_at: :desc)

    # Apply filter for suspicious people
    if @filter == "suspicious"
      @people = @people.suspicious
    end

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

    redirect_to people_list_path, notice: "Successfully deleted all #{count} suspicious #{'person'.pluralize(count)}", status: :see_other
  end

  def organizations_list
    @search = params[:search].to_s.strip
    @organizations = Organization.order(created_at: :desc)

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
      if original_user
        start_new_session_for original_user
      end
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
        if person.organizations.empty?
          updates_made << "(Note: Person has no production company associations)"
        end
      end
    end

    redirect_to superadmin_path, notice: "Successfully changed email from #{old_email} to #{new_email}. Updated: #{updates_made.join(', ')}"
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
    if params[:user_id].present?
      @email_logs = @email_logs.where(user_id: params[:user_id])
    end

    # Filter by recipient if requested
    if params[:recipient].present?
      @email_logs = @email_logs.where("recipient LIKE ?", "%#{params[:recipient]}%")
    end
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
    job = failed_execution.job

    # Create a new job with the same parameters
    ActiveJob::Base.queue_adapter.enqueue(
      job.class_name.constantize.new(*JSON.parse(job.arguments))
    )

    redirect_to queue_failed_path, notice: "Job queued for retry"
  rescue => e
    redirect_to queue_failed_path, alert: "Failed to retry job: #{e.message}"
  end

  def queue_delete_job
    job = SolidQueue::Job.find(params[:id])
    job.destroy
    redirect_to queue_monitor_path, notice: "Job deleted"
  rescue => e
    redirect_to queue_monitor_path, alert: "Failed to delete job: #{e.message}"
  end

  def queue_clear_failed
    count = SolidQueue::FailedExecution.count
    SolidQueue::FailedExecution.destroy_all
    redirect_to queue_monitor_path, notice: "Cleared #{count} failed jobs"
  rescue => e
    redirect_to queue_monitor_path, alert: "Failed to clear failed jobs: #{e.message}"
  end

  def queue_clear_pending
    count = SolidQueue::Job.where(finished_at: nil).count
    SolidQueue::Job.where(finished_at: nil).destroy_all
    redirect_to queue_monitor_path, notice: "Cleared #{count} pending jobs"
  rescue => e
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

    # Key structure analysis
    @flat_keys_count = ActiveStorage::Blob.where("key NOT LIKE '%/%'").count
    @hierarchical_keys_count = ActiveStorage::Blob.where("key LIKE '%/%'").count
    @flat_keys_by_service = ActiveStorage::Blob.where("key NOT LIKE '%/%'").group(:service_name).count

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
  rescue => e
    redirect_to storage_monitor_path, alert: "Failed to cleanup orphans: #{e.message}"
  end

  def storage_cleanup_legacy
    legacy = ActiveStorage::Attachment.where(record_type: "Person", name: %w[headshot resume])
    count = legacy.count
    legacy.delete_all
    redirect_to storage_monitor_path, notice: "Deleted #{count} legacy Person attachments"
  rescue => e
    redirect_to storage_monitor_path, alert: "Failed to cleanup legacy attachments: #{e.message}"
  end

  def storage_migrate_keys
    # Auto-detect service with flat keys if not specified
    service_name = params[:service].presence
    unless service_name
      service_name = ActiveStorage::Blob
        .where("key NOT LIKE '%/%'")
        .group(:service_name)
        .count
        .max_by { |_, count| count }
        &.first
    end

    unless service_name
      redirect_to storage_monitor_path, notice: "No flat keys to migrate"
      return
    end

    migrated = 0
    errors = []

    # Only migrate blobs with flat keys (no /)
    blobs_to_migrate = ActiveStorage::Blob
      .where(service_name: service_name)
      .where("key NOT LIKE '%/%'")
      .joins(:attachments)
      .includes(:attachments)
      .distinct

    # Get the storage service
    storage_service = ActiveStorage::Blob.services.fetch(service_name.to_sym)

    blobs_to_migrate.find_each do |blob|
      begin
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
        old_key = blob.key
        blob.update_column(:key, new_key)

        # Note: Old key is preserved. Run delete_old_keys after verifying migration.

        migrated += 1
      rescue => e
        errors << "Blob #{blob.id}: #{e.message}"
      end
    end

    message = "Migrated #{migrated} blobs to hierarchical keys"
    message += ". Errors: #{errors.first(3).join('; ')}" if errors.any?

    redirect_to storage_monitor_path, notice: message
  rescue => e
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
      rescue => e
        errors << "#{key}: #{e.message}"
      end
    end

    message = "Deleted #{deleted_count} orphaned S3 files (#{ActionController::Base.helpers.number_to_human_size(deleted_size)})"
    message += ". Errors: #{errors.first(3).join('; ')}" if errors.any?

    redirect_to storage_monitor_path, notice: message
  rescue => e
    redirect_to storage_monitor_path, alert: "S3 cleanup failed: #{e.message}"
  end

  # Cache Monitor
  def cache
    if solid_cache_available?
      @entry_count = SolidCache::Entry.count
      @total_bytes = SolidCache::Entry.sum(:byte_size)
      @max_size = 256.megabytes
      @usage_percent = @max_size > 0 ? (@total_bytes.to_f / @max_size * 100).round(1) : 0

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
  rescue => e
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
  rescue => e
    redirect_to cache_monitor_path, alert: "Pattern clear failed: #{e.message}"
  end

  private

  def require_superadmin
    unless Current.user&.superadmin?
      redirect_to my_dashboard_path
    end
  end

  # Cache helper methods
  def solid_cache_available?
    defined?(SolidCache::Entry) && SolidCache::Entry.table_exists?
  rescue
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
    ranges.reject { |_, v| v == 0 }
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
  rescue
    "unknown"
  end

  def decode_key(key_binary)
    key_binary.to_s.force_encoding("UTF-8")
  rescue
    key_binary.to_s
  end

  def test_cache_connectivity
    test_key = "superadmin_cache_test_#{Time.current.to_i}"
    Rails.cache.write(test_key, "ok", expires_in: 1.minute)
    result = Rails.cache.read(test_key) == "ok"
    Rails.cache.delete(test_key)
    result
  rescue
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
end
