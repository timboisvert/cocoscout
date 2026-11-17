# frozen_string_literal: true

# One sign-up decided on its own page, for a cycle with no audition sessions
# (Tim, 2026-11-17): add them to the talent pool, or tell them they weren't
# chosen, and send them the email the manager just read, without waiting for
# the casting board's Finalize & notify.
#
# It does for one person what Finalize & notify does for each person, and it
# leaves the same record: a finalized CastAssignmentStage, so the casting board
# shows them as decided and notified and never emails them again.
class AuditionRequestDecision
  DECISIONS = %w[cast rejected].freeze

  Result = Struct.new(:messages_sent, :emails_sent, keyword_init: true)

  def self.call(...)
    new(...).call
  end

  # subject and body: the email as the manager left it in the modal. [Name]
  # is filled in per person (a group's members each get their own).
  def initialize(audition_request:, decision:, subject:, body:, sender:)
    @request = audition_request
    @decision = decision.to_s
    @subject = subject.to_s.strip
    @body = body.to_s.strip
    @sender = sender
    raise ArgumentError, "Unknown decision: #{decision}" unless DECISIONS.include?(@decision)
  end

  def call
    cycle = @request.audition_cycle
    production = cycle.production
    assignable = @request.requestable
    talent_pool = production.effective_talent_pool

    ActiveRecord::Base.transaction do
      if @decision == "cast"
        TalentPoolMembership.find_or_create_by!(talent_pool_id: talent_pool.id,
                                                member_type: assignable.class.name, member_id: assignable.id)
      elsif assignable.is_a?(Person)
        assignable.update!(casting_notification_sent_at: Time.current, notified_for_audition_cycle_id: cycle.id)
      end

      # One stage per person per cycle and pool (an archived one included).
      stage = CastAssignmentStage.find_or_initialize_by(audition_cycle_id: cycle.id, talent_pool_id: talent_pool.id,
                                                        assignable_type: assignable.class.name, assignable_id: assignable.id)
      stage.update!(decision_type: @decision, status: :finalized, archived_at: nil, notification_email: @body)
    end

    notifications = recipients(assignable).filter_map do |person|
      next if person.email.blank?

      { person: person, talent_pool: talent_pool,
        subject: @subject.gsub("[Name]", first_name(person)), body: @body.gsub("[Name]", first_name(person)) }
    end

    results = AuditionNotificationService.send_casting_results(
      production: production, audition_cycle: cycle, sender: @sender,
      cast_assignments: @decision == "cast" ? notifications : [],
      rejections: @decision == "rejected" ? notifications.map { |n| n.except(:talent_pool) } : []
    )
    Result.new(messages_sent: results[:messages_sent], emails_sent: results[:emails_sent])
  end

  private

  def first_name(person)
    person.first_name.presence || person.name
  end

  def recipients(assignable)
    return [ assignable ] unless assignable.is_a?(Group)

    assignable.group_memberships.select(&:notifications_enabled?).map(&:person)
  end
end
