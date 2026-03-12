# frozen_string_literal: true

class CocobaseService
  # Generate a Cocobase instance for a show if the production has a matching template.
  # Called after a show is created.
  def self.generate_for_show(show)
    template = show.production.cocobase_template
    return unless template&.matches_event_type?(show.event_type)

    # Don't create duplicate
    return if show.cocobase.present?

    cocobase = show.create_cocobase!(
      cocobase_template: template,
      deadline: calculate_deadline(show, template),
      status: :open
    )

    copy_template_fields(cocobase, template)
    cocobase
  end

  # Generate CocobaseSubmissions for all cast members of a show.
  # Called when casting is finalized.
  def self.generate_submissions_for_show(show)
    cocobase = show.cocobase
    return unless cocobase

    # Gather unique assignables (Person or Group) from cast
    assignables = show.show_person_role_assignments
                      .where.not(assignable_type: nil)
                      .select(:assignable_type, :assignable_id)
                      .distinct
                      .map(&:assignable)
                      .compact

    assignables.each do |assignable|
      submission = cocobase.cocobase_submissions.find_or_create_by!(
        submittable: assignable
      )

      # Notify the person/group about the new cocobase submission
      notify_submission_created(submission) if submission.previously_new_record?
    end
  end

  # Copy template fields to a cocobase instance
  def self.copy_template_fields(cocobase, template)
    template.cocobase_template_fields.each do |tf|
      cocobase.cocobase_fields.create!(
        label: tf.label,
        description: tf.description,
        field_type: tf.field_type,
        required: tf.required,
        position: tf.position,
        config: tf.config
      )
    end
  end

  # Calculate deadline from show date minus template default days
  def self.calculate_deadline(show, template)
    return nil unless show.date_and_time.present?

    show.date_and_time - template.default_deadline_days.days
  end

  # Notify an assignable about a new cocobase submission
  def self.notify_submission_created(submission)
    cocobase = submission.cocobase
    show = cocobase.show
    production = show.production
    entity = submission.submittable

    deadline_text = cocobase.deadline.present? ? " by #{cocobase.deadline.strftime('%b %-d, %Y')}" : ""
    subject = "Cocobase: Materials needed for #{show.event_type.titleize} on #{show.date_and_time.strftime('%b %-d')}"
    body = "You have a Cocobase submission to complete for the #{show.event_type} on " \
           "#{show.date_and_time.strftime('%b %-d, %Y at %l:%M %p')}#{deadline_text}. " \
           "Please visit your Open Requests page to submit the required materials."

    people = entity.is_a?(Person) ? [ entity ] : entity.members.to_a
    people.each do |person|
      MessageService.send_direct(
        sender: nil,
        recipient_person: person,
        subject: subject,
        body: body,
        production: production,
        system_generated: true
      )
    end
  rescue => e
    Rails.logger.error "[CocobaseService] Failed sending notification for submission #{submission.id}: #{e.message}"
  end
end
