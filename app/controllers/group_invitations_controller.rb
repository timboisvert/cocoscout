# frozen_string_literal: true

class GroupInvitationsController < ApplicationController
  allow_unauthenticated_access only: %i[accept do_accept]
  before_action :set_group, only: %i[create revoke]
  before_action :check_group_access, only: %i[create revoke]

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

      # Send notification message if user has an account
      if existing_person.user.present?
        group_url = Rails.application.routes.url_helpers.group_url(
          @group,
          host: ENV.fetch("HOST", "localhost:3000")
        )

        rendered = ContentTemplateService.render("group_member_added", {
          recipient_name: existing_person.first_name || "there",
          group_name: @group.name,
          added_by_name: Current.user.person&.full_name || "A group member",
          group_url: group_url,
          custom_message: params[:invitation_message]
        })

        MessageService.send_direct(
          sender: Current.user,
          recipient_person: existing_person,
          subject: rendered[:subject],
          body: rendered[:body],
          production: nil,
          organization: nil
        )
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update(
              "notice-container",
              partial: "shared/notice",
              locals: { notice: "#{existing_person.name} has been added to the group" }
            ),
            turbo_stream.replace("members", partial: "groups/members_section",
                                            locals: { group: @group, membership: @membership }),
            turbo_stream.append_all("body",
                                    "<script>document.querySelector('[data-group-members-target=\"inviteModal\"]').classList.add('hidden')</script>")
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
        default_subject = ContentTemplateService.render_subject("group_invitation", {
          group_name: @group.name
        })
        invitation_subject = params[:invitation_subject] || default_subject
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
              turbo_stream.append_all("body",
                                      "<script>document.querySelector('[data-group-members-target=\"inviteModal\"]').classList.add('hidden')</script>")
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
    return unless Current.user

    # User is signed in, just show confirmation
    @person = Current.user.person
  end

  def do_accept
    @invitation = GroupInvitation.find_by!(token: params[:token])

    if @invitation.accepted?
      redirect_to root_path, notice: "This invitation has already been accepted"
      return
    end

    # Try to find existing user
    user = User.find_by(email_address: @invitation.email.downcase)
    person = Person.find_by(email: @invitation.email.downcase)

    # If not signed in, handle password
    if Current.user
      # Already signed in
      user = Current.user
      person = user.person
    else
      if user && params[:password].present?
        # Existing user setting/updating password
        user.password = params[:password]
        unless user.valid?
          @user = user
          render :accept, status: :unprocessable_entity and return
        end
        user.save!
      elsif params[:password].present?
        # New user - create account
        user = User.new(email_address: @invitation.email.downcase, password: params[:password])
        unless user.save
          @user = user
          render :accept, status: :unprocessable_entity and return
        end
      else
        # No password provided
        @user = User.new(email_address: @invitation.email.downcase)
        @user.errors.add(:password, "can't be blank")
        render :accept, status: :unprocessable_entity and return
      end

      # Ensure person exists and is linked to user
      if person
        # Link existing person to user if not already linked
        unless person.user
          person.user = user
          person.save!
        end
      else
        person = Person.create!(
          email: @invitation.email.downcase,
          name: @invitation.name,
          user: user
        )
      end

      # Sign the user in
      start_new_session_for user
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

  def revoke
    invitation = @group.group_invitations.pending.find(params[:id])
    invitation.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update(
            "notice-container",
            partial: "shared/notice",
            locals: { notice: "Invitation to #{invitation.email} has been revoked" }
          ),
          turbo_stream.replace("members", partial: "groups/members_section",
                                          locals: { group: @group, membership: @membership })
        ]
      end
    end
  end

  private

  def set_group
    @group = Group.find(params[:group_id])
    @membership = @group.group_memberships.find_by(person: Current.user.person)
  end

  def check_group_access
    return if @membership&.owner? || @membership&.write?

    redirect_to root_path, alert: "You don't have permission to invite members to this group"
  end
end
