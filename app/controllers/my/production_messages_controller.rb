class My::ProductionMessagesController < ApplicationController
  before_action :require_authentication
  before_action :set_production

  def create
    subject = params[:subject]
    body = params[:body]
    images = params[:images]&.reject(&:blank?)

    if subject.blank? || body.blank?
      redirect_back fallback_location: my_messages_path, alert: "Subject and message are required"
      return
    end

    message = MessageService.send_to_production_team(
      production: @production,
      sender: Current.user,
      subject: subject,
      body: body
    )

    # Attach images if provided
    message&.images&.attach(images) if images.present?

    # Attach poll if provided
    attach_poll!(message) if poll_params_present?

    redirect_to my_messages_path, notice: "Message sent to #{@production.name} team"
  end

  private

  def set_production
    # Get all productions user can contact (via talent pool membership)
    contactable_production_ids = contactable_productions.pluck(:id)
    @production = Production.where(id: contactable_production_ids).find(params[:production_id])
  end

  def contactable_productions
    return Production.none unless Current.user.person

    people_ids = Current.user.people.active.pluck(:id)
    return Production.none if people_ids.empty?

    group_ids = GroupMembership.where(person_id: people_ids).pluck(:group_id)

    production_ids = Set.new

    # Productions via person's direct talent pool memberships
    person_production_ids = TalentPoolMembership
      .where(member_type: "Person", member_id: people_ids)
      .joins(:talent_pool)
      .pluck("talent_pools.production_id")
    production_ids.merge(person_production_ids)

    # Productions via shared talent pools
    if people_ids.any?
      shared_person_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Person", member_id: people_ids })
        .pluck(:id)
      production_ids.merge(shared_person_production_ids)
    end

    # Productions via group's talent pool memberships
    if group_ids.any?
      group_production_ids = TalentPoolMembership
        .where(member_type: "Group", member_id: group_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(group_production_ids)

      shared_group_production_ids = Production
        .joins(talent_pool_shares: { talent_pool: :talent_pool_memberships })
        .where(talent_pool_memberships: { member_type: "Group", member_id: group_ids })
        .pluck(:id)
      production_ids.merge(shared_group_production_ids)
    end

    # Productions where user is cast in shows (person or group assignments)
    if people_ids.any?
      cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Person", assignable_id: people_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(cast_production_ids)
    end

    if group_ids.any?
      group_cast_production_ids = Production
        .joins(shows: :show_person_role_assignments)
        .where(show_person_role_assignments: { assignable_type: "Group", assignable_id: group_ids })
        .distinct
        .pluck(:id)
      production_ids.merge(group_cast_production_ids)
    end

    Production.where(id: production_ids)
  end

  def poll_params_present?
    params[:message_poll].present? && params[:message_poll][:question].present?
  end

  def attach_poll!(message)
    return unless message && poll_params_present?

    poll_attrs = params.require(:message_poll).permit(
      :question, :max_votes,
      message_poll_options_attributes: [ :text, :position ]
    ).to_h

    # Default max_votes to 1 if not set
    poll_attrs["max_votes"] ||= 1

    # Filter out blank options
    if poll_attrs["message_poll_options_attributes"]
      poll_attrs["message_poll_options_attributes"] = poll_attrs["message_poll_options_attributes"]
        .values
        .reject { |opt| opt["text"].blank? }
        .each_with_index.map { |opt, i| opt.merge("position" => i) }
    end

    message.create_message_poll!(poll_attrs)
  end
end
