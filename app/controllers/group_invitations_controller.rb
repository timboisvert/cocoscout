class GroupInvitationsController < ApplicationController
  allow_unauthenticated_access only: [ :accept, :do_accept ]
  before_action :set_group, only: [ :create ]
  before_action :check_group_access, only: [ :create ]

  def create
    # Check if person already exists with this email
    existing_person = Person.find_by(email: params[:email].downcase.strip)

    if existing_person
      # Person exists - check if already a member
      existing_membership = @group.group_memberships.find_by(person: existing_person)

      if existing_membership
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "notice-container",
              partial: "shared/notice",
              locals: { notice: "#{existing_person.name} is already a member of this group" }
            )
          end
        end
        return
      end

      # Create membership directly
      @group.group_memberships.create!(
        person: existing_person,
        permission_level: params[:permission_level] || "view"
      )

      # Send notification email
      GroupInvitationMailer.existing_member_added(
        existing_person,
        @group,
        Current.user.person,
        params[:invitation_subject],
        params[:invitation_message]
      ).deliver_later

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update(
              "notice-container",
              partial: "shared/notice",
              locals: { notice: "#{existing_person.name} has been added to the group" }
            ),
            turbo_stream.replace("members", partial: "groups/members_section", locals: { group: @group, membership: @membership }),
            turbo_stream.append_all("body", "<script>document.querySelector('[data-group-members-target=\"inviteModal\"]').classList.add('hidden')</script>")
          ]
        end
      end
    else
      # Person doesn't exist - create invitation
      invitation = @group.group_invitations.build(
        email: params[:email],
        name: params[:name],
        permission_level: params[:permission_level] || "view",
        invited_by: Current.user.person
      )

      if invitation.save
        # Send invitation email
        invitation_subject = params[:invitation_subject] || "You've been invited to join #{@group.name} on CocoScout"
        invitation_message = params[:invitation_message]

        GroupInvitationMailer.invitation(invitation, invitation_subject, invitation_message).deliver_later

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update(
                "notice-container",
                partial: "shared/notice",
                locals: { notice: "Invitation sent to #{params[:email]}" }
              ),
              turbo_stream.append_all("body", "<script>document.querySelector('[data-group-members-target=\"inviteModal\"]').classList.add('hidden')</script>")
            ]
          end
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "notice-container",
              partial: "shared/notice",
              locals: { notice: "Error: #{invitation.errors.full_messages.join(', ')}" }
            )
          end
        end
      end
    end
  end

  def accept
    @invitation = GroupInvitation.find_by!(token: params[:token])

    if @invitation.accepted?
      redirect_to root_path, notice: "This invitation has already been accepted"
      return
    end

    # Check if user is signed in
    if Current.user
      # User is signed in, just show confirmation
      @person = Current.user.person
    end
  end

  def do_accept
    @invitation = GroupInvitation.find_by!(token: params[:token])

    if @invitation.accepted?
      redirect_to root_path, notice: "This invitation has already been accepted"
      return
    end

    user = Current.user
    person = user&.person

    # If no existing person, create one
    unless person
      # Check if person exists with this email
      person = Person.find_by(email: @invitation.email)

      unless person
        # Create new person
        person = Person.create!(
          email: @invitation.email,
          name: @invitation.name,
          user: user
        )
      end
    end

    # Create group membership
    @invitation.group.group_memberships.create!(
      person: person,
      permission_level: @invitation.permission_level
    )

    # Mark invitation as accepted
    @invitation.update!(accepted_at: Time.current)

    redirect_to edit_group_path(@invitation.group), notice: "You've joined #{@invitation.group.name}"
  end

  private

  def set_group
    @group = Group.find(params[:group_id])
    @membership = @group.group_memberships.find_by(person: Current.user.person)
  end

  def check_group_access
    unless @membership&.owner? || @membership&.write?
      redirect_to root_path, alert: "You don't have permission to invite members to this group"
    end
  end
end
