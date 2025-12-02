class SuperadminController < ApplicationController
  before_action :require_superadmin, only: [ :index, :impersonate, :change_email, :queue, :queue_failed, :queue_retry, :queue_delete_job, :queue_clear_failed, :queue_clear_pending ]
  before_action :hide_sidebar

  def hide_sidebar
    @show_my_sidebar = false
  end

  def index
    @users = User.order(:email_address)

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
    @email_logs = EmailLog.includes(:user).order(sent_at: :desc).limit(100)

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

  private

  def require_superadmin
    unless Current.user&.superadmin?
      redirect_to my_dashboard_path
    end
  end
end
