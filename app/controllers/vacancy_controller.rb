# frozen_string_literal: true

class VacancyController < ApplicationController
  allow_unauthenticated_access only: %i[show confirm success]
  before_action :set_person_from_token, only: %i[show confirm success]
  before_action :set_show, only: %i[show confirm success]

  def show
    # Get person's direct assignments
    @person_assignments = @show.show_person_role_assignments
                               .where(assignable: @person)
                               .includes(:role)
                               .order("roles.position ASC")

    # Get group assignments for groups the person is a member of
    @groups = @person.groups.active.to_a
    @groups_by_id = @groups.index_by(&:id)
    @group_assignments = @show.show_person_role_assignments
                              .where(assignable_type: "Group", assignable_id: @groups.map(&:id))
                              .includes(:role)
                              .order("roles.position ASC")

    @all_assignments = @person_assignments + @group_assignments

    if @all_assignments.empty?
      redirect_to root_path, alert: "You don't have any assignments for this show."
      return
    end
  end

  def confirm
    role_ids = params[:role_ids] || []

    if role_ids.empty?
      redirect_to vacancy_path(@show, token: @token), alert: "Please select at least one role."
      return
    end

    @vacancies_created = []

    # Get groups the person can act on behalf of
    group_ids = @person.groups.active.pluck(:id)

    ActiveRecord::Base.transaction do
      role_ids.each do |assignment_key|
        # Parse the assignment key (format: "role_id:assignable_type:assignable_id")
        role_id, assignable_type, assignable_id = assignment_key.split(":")

        # Find the assignment, validating the person has access
        assignment = if assignable_type == "Person" && assignable_id.to_i == @person.id
          @show.show_person_role_assignments.find_by(
            role_id: role_id,
            assignable_type: "Person",
            assignable_id: @person.id
          )
        elsif assignable_type == "Group" && group_ids.include?(assignable_id.to_i)
          @show.show_person_role_assignments.find_by(
            role_id: role_id,
            assignable_type: "Group",
            assignable_id: assignable_id
          )
        end

        next unless assignment

        # Create the vacancy with the actual assignable (Person or Group)
        vacancy = RoleVacancy.create!(
          show: @show,
          role: assignment.role,
          vacated_by: assignment.assignable,
          vacated_at: Time.current,
          status: :open
        )

        @vacancies_created << vacancy

        # Remove the assignment
        assignment.destroy!
      end
    end

    redirect_to vacancy_success_path(@show, token: @token, count: @vacancies_created.count)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to vacancy_path(@show, token: @token), alert: "Something went wrong: #{e.message}"
  end

  def success
    @count = params[:count].to_i
  end

  private

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
