# frozen_string_literal: true

class VacancyController < ApplicationController
  allow_unauthenticated_access only: %i[show confirm success]
  before_action :set_person_from_token, only: %i[show confirm success]
  before_action :set_show, only: %i[show confirm success]

  def show
    @all_assignments = held_assignments

    if @all_assignments.empty?
      redirect_to root_path, alert: "You don't have any assignments for this show."
      return
    end

    # On a show cast by acts, someone with more than one act chooses which
    # acts they can't make: every act starts ticked, and unticking one keeps
    # it (Tim, 2026-11-24). One act, or a show cast by roles, is the single
    # choice it always was.
    @choose_several = choose_several?(@all_assignments.size)
    @unit = unit_for(@all_assignments.map(&:role))
    @lineup_numbers = lineup_numbers
  end

  def confirm
    role_ids = Array(params[:role_ids]).map(&:to_s).uniq
    affected_show_ids = params[:affected_show_ids] || [ @show.id ]

    if role_ids.empty?
      redirect_to vacancy_path(@show, token: @token), alert: "Please select at least one role."
      return
    end

    @vacancies_created = []

    # Only what this person still holds on the show can be given up: a key
    # for someone else's assignment, or for one already given up, finds nothing.
    held = held_assignments.index_by { |assignment| assignment_key(assignment) }
    chosen = role_ids.filter_map { |key| held[key] }

    if chosen.empty?
      redirect_to vacancy_path(@show, token: @token), alert: "Please select at least one role."
      return
    end

    # Validate affected shows are linked to this show
    is_linked = @show.linked?
    valid_affected_show_ids = if is_linked
      linked_show_ids = @show.linked_shows.pluck(:id) + [ @show.id ]
      affected_show_ids.map(&:to_i) & linked_show_ids
    else
      [ @show.id ]
    end

    # Several at once reach the production team as one notice that names
    # every act, not one notice per act.
    together = chosen.size > 1

    ActiveRecord::Base.transaction do
      chosen.each do |assignment|
        vacancy = RoleVacancy.create!(
          show: @show,
          role_id: assignment.role_id,
          vacated_by: assignment.assignable,
          vacated_at: Time.current,
          status: :open,
          noticed_together: together
        )

        # Add affected shows to the vacancy
        valid_affected_show_ids.each do |show_id|
          vacancy.role_vacancy_shows.create!(show_id: show_id)
        end

        @vacancies_created << vacancy

        # Only remove the assignment for non-linked shows
        # For linked shows, the producer decides what to do
        unless is_linked
          assignment.destroy!

          # Unfinalize casting since we now have an open role
          @show.reopen_casting! if @show.casting_finalized?
        end
      end
    end

    if together && @show.date_and_time > Time.current
      VacancyNotificationJob.perform_later(@vacancies_created.map(&:id), "created")
    end

    redirect_to vacancy_success_path(@show, token: @token, count: @vacancies_created.count, affected_show_ids: valid_affected_show_ids.join(","),
                                            linked: is_linked ? "1" : "0", vacancy_ids: @vacancies_created.map(&:id).join(","))
  rescue ActiveRecord::RecordInvalid => e
    redirect_to vacancy_path(@show, token: @token), alert: "Something went wrong: #{e.message}"
  end

  def success
    @count = params[:count].to_i
    @is_linked = params[:linked] == "1"
    affected_show_ids = params[:affected_show_ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    @affected_shows = Show.where(id: affected_show_ids).order(:date_and_time).to_a

    # What was just given up and what is kept, for someone who had several
    # acts: only this person's own vacancies on this show are ever listed.
    vacancy_ids = params[:vacancy_ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    @lineup_numbers = lineup_numbers
    @vacated = RoleVacancy.where(id: vacancy_ids, show: @show).includes(:role).select { |vacancy| mine?(vacancy.vacated_by_type, vacancy.vacated_by_id) }
                          .sort_by { |vacancy| [ @lineup_numbers[vacancy.role_id] || 0, vacancy.role&.position || 0 ] }
    @kept = held_assignments
    @chose_several = @vacated.any? && choose_several?(@vacated.size + @kept.size)
    @unit = unit_for(@vacated.map(&:role) + @kept.map(&:role))
  end

  private

  # Everyone this link speaks for: the person's own profiles, and the groups
  # any of those profiles is a member of.
  def my_people_ids
    @my_people_ids ||= @person.user ? @person.user.people.active.pluck(:id) : [ @person.id ]
  end

  def my_group_ids
    @my_group_ids ||= Group.active.joins(:group_memberships).where(group_memberships: { person_id: my_people_ids }).distinct.pluck(:id)
  end

  def mine?(type, id)
    (type == "Person" && my_people_ids.include?(id)) || (type == "Group" && my_group_ids.include?(id))
  end

  # What this person still holds on the show: their own assignments first,
  # then their groups', each in the show's order. An assignment already given
  # up isn't held; on a linked show it stays on the cast until the production
  # team decides, so it is left out by its vacancy.
  def held_assignments
    assignments = @show.show_person_role_assignments.includes(:role, :assignable).to_a
                       .select { |assignment| assignment.role && mine?(assignment.assignable_type, assignment.assignable_id) }
    given_up = RoleVacancy.where(show: @show).where.not(status: %w[filled cancelled]).pluck(:role_id, :vacated_by_type, :vacated_by_id).to_set
    assignments.reject! { |assignment| given_up.include?([ assignment.role_id, assignment.assignable_type, assignment.assignable_id ]) }
    assignments.sort_by { |assignment| [ assignment.assignable_type == "Person" ? 0 : 1, assignment.role.position || 0 ] }
  end

  # Format: "role_id:assignable_type:assignable_id"
  def assignment_key(assignment)
    "#{assignment.role_id}:#{assignment.assignable_type}:#{assignment.assignable_id}"
  end

  def choose_several?(count)
    @show.act_based? && count > 1
  end

  # What the page calls one of them: an act, unless a show role (an MC, say)
  # is among them.
  def unit_for(roles)
    roles.compact.all? { |role| role.act?(show: @show) } ? "act" : "assignment"
  end

  def lineup_numbers
    @show.act_based? ? Role.lineup_numbers_for(@show.available_roles.to_a) : {}
  end

  def set_person_from_token
    @token = params[:token]

    unless @token.present?
      redirect_to root_path, alert: "Invalid or expired link."
      return
    end

    # Token format: person_id signed with Rails message verifier
    @person = find_person_from_token(@token)

    unless @person
      redirect_to root_path, alert: "Invalid or expired link."
    end
  end

  def set_show
    @show = Show.find_by(id: params[:show_id])

    unless @show
      redirect_to root_path, alert: "Show not found."
    end
  end

  def find_person_from_token(token)
    verifier = Rails.application.message_verifier(:vacancy)
    person_id = verifier.verified(token, purpose: :vacancy)
    Person.find_by(id: person_id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  class << self
    def generate_token(person)
      verifier = Rails.application.message_verifier(:vacancy)
      verifier.generate(person.id, purpose: :vacancy, expires_in: 7.days)
    end
  end
end
