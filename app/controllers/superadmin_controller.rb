class SuperadminController < ApplicationController
  before_action :require_superadmin, only: [ :index, :impersonate, :change_email, :queue, :queue_failed, :queue_retry, :queue_delete_job, :queue_clear_failed, :queue_clear_pending, :organizations_list, :organization_detail ]
  before_action :hide_sidebar

  def hide_sidebar
    @show_my_sidebar = false
  end

  def index
    @users = User.order(:email_address)

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
    service_name = params[:service] || "amazon"
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

  private

  def require_superadmin
    unless Current.user&.superadmin?
      redirect_to my_dashboard_path
    end
  end
end
