# frozen_string_literal: true

module My
  class ShoutoutsController < ApplicationController
    before_action :require_authentication
    before_action :set_shoutee, only: [ :create ]

    def index
      @show_my_sidebar = true
      @person = Current.user.person

      # Get received shoutouts for the current user's person (only current versions)
      @received_shoutouts = @person.received_shoutouts
                                   .left_joins(:replacement)
                                   .where(replacement: { id: nil })
                                   .newest_first

      # Get given shoutouts by the current user (only current versions)
      @given_shoutouts = @person.given_shoutouts
                                .left_joins(:replacement)
                                .where(replacement: { id: nil })
                                .newest_first
                                .includes(:shoutee)

      # Determine which tab to show
      @active_tab = params[:tab] || "received"

      # Check if we're creating a new shoutout (shoutee params present)
      return unless params[:shoutee_type].present? && params[:shoutee_id].present?

      @shoutee = case params[:shoutee_type]
      when "Person"
                   Person.find_by(id: params[:shoutee_id])
      when "Group"
                   Group.find_by(id: params[:shoutee_id])
      end

      # Check if user has already given this person/group a shoutout
      if @shoutee.present?
        @existing_shoutout = Current.user.person.given_shoutouts
                                    .where(shoutee: @shoutee)
                                    .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
                                    .first
      end

      # Auto-switch to given tab when creating a shoutout
      @active_tab = "given" if @shoutee.present?
    end

    def search_people_and_groups
      query = params[:q].to_s.strip
      service = ShoutoutSearchService.new(query, Current.user, method(:url_for))
      results = service.call

      render json: results
    end

    def check_existing_shoutout
      shoutee_type = params[:shoutee_type]
      shoutee_id = params[:shoutee_id]
      service = ShoutoutExistenceCheckService.new(shoutee_type, shoutee_id, Current.user)
      has_existing = service.call

      render json: { has_existing_shoutout: has_existing }
    end

    def create
      # Handle invite flow
      return handle_invite_shoutout if params[:shoutee_type] == "invite"

      # If shoutee is a group and the current user is a member, deny creation
      if @shoutee.is_a?(Group) && @shoutee.group_memberships.exists?(person: Current.user.person)
        redirect_to my_shoutouts_path(tab: "given"), alert: "You cannot give a shoutout to a group you belong to."
        return
      end

      # Check if user has already given this person/group a shoutout
      existing_shoutout = Current.user.person.given_shoutouts
                                 .where(shoutee: @shoutee)
                                 .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
                                 .first

      @shoutout = Shoutout.new(shoutout_params)
      @shoutout.author = Current.user.person
      @shoutout.shoutee = @shoutee

      # Link to existing shoutout if present
      @shoutout.replaces_shoutout = existing_shoutout if existing_shoutout

      if @shoutout.save
        # Send notification to recipient based on their account status
        send_shoutout_notification(@shoutout)
        redirect_to my_shoutouts_path(tab: "given"), notice: "Shoutout sent successfully!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def send_shoutout_notification(shoutout)
      shoutee = shoutout.shoutee
      return unless shoutee.respond_to?(:email) && shoutee.email.present?

      # Check notification preferences
      return if shoutee.user.present? && !shoutee.user.notification_enabled?(:shoutouts)

      shoutout_url = Rails.application.routes.url_helpers.profile_url(
        shoutee,
        host: ENV.fetch("HOST", "localhost:3000")
      )

      variables = {
        recipient_name: shoutee.first_name || "there",
        author_name: shoutout.author.name,
        shoutout_message: shoutout.body,
        shoutout_url: shoutout_url
      }

      if shoutee.user.present?
        # User has an account - send in-app message (shoutout_notification is channel: :message)
        rendered = ContentTemplateService.render("shoutout_notification", variables)
        MessageService.send_direct(
          sender: Current.user,
          recipient_person: shoutee,
          subject: rendered[:subject],
          body: rendered[:body],
          organization: nil
        )
      else
        # No account - send email via ShoutoutMailer
        ShoutoutMailer.shoutout_received(shoutout).deliver_later
      end
    end

    def handle_invite_shoutout
      invite_name = params[:invite_name]
      invite_email = params[:invite_email]

      if invite_name.blank? || invite_email.blank?
        redirect_to my_shoutouts_path(tab: "given", show_form: "true"),
                    alert: "Name and email are required to invite someone."
        return
      end

      # Normalize email
      invite_email = invite_email.downcase.strip

      # First, check if a person with this email already exists
      existing_person = Person.find_by(email: invite_email)

      if existing_person
        # Person exists - give them the shoutout directly
        @shoutee = existing_person

        # Check for existing shoutout
        existing_shoutout = Current.user.person.given_shoutouts
                                   .where(shoutee: @shoutee)
                                   .where(id: Shoutout.left_joins(:replacement).where(replacement: { id: nil }).select(:id))
                                   .first

        @shoutout = Shoutout.new(shoutout_params)
        @shoutout.author = Current.user.person
        @shoutout.shoutee = @shoutee

        @shoutout.replaces_shoutout = existing_shoutout if existing_shoutout

        if @shoutout.save
          # Send notification to recipient
          send_shoutout_notification(@shoutout)
          redirect_to my_shoutouts_path(tab: "given"), notice: "Shoutout sent successfully!"
        else
          redirect_to my_shoutouts_path(tab: "given", show_form: "true"), alert: "Could not save shoutout."
        end
      else
        # Person doesn't exist - create user, person, and send invitation

        # Check if user already exists
        existing_user = User.find_by(email_address: invite_email)

        if existing_user
          redirect_to my_shoutouts_path(tab: "given", show_form: "true"),
                      alert: "A user with this email already exists."
          return
        end

        # Create user with random password
        user = User.create!(
          email_address: invite_email,
          password: User.generate_secure_password
        )

        # Create person
        person = Person.create!(
          name: invite_name,
          email: invite_email,
          user: user
        )

        # Create shoutout
        @shoutout = Shoutout.new(shoutout_params)
        @shoutout.author = Current.user.person
        @shoutout.shoutee = person

        if @shoutout.save
          # Create person invitation
          person_invitation = PersonInvitation.create!(
            email: person.email,
            organization: nil
          )

          # Send invitation email using template
          invitation_subject = ContentTemplateService.render_subject("shoutout_invitation", {
            author_name: Current.user.person.name
          })
          invitation_message = ContentTemplateService.render_body("shoutout_invitation", {
            author_name: Current.user.person.name,
            setup_url: "[setup link will be included]"
          })

          Manage::PersonMailer.person_invitation(person_invitation, invitation_subject,
                                                 invitation_message).deliver_later

          redirect_to my_shoutouts_path(tab: "given"),
                      notice: "Shoutout sent and invitation delivered to #{invite_name}!"
        else
          redirect_to my_shoutouts_path(tab: "given", show_form: "true"), alert: "Could not save shoutout."
        end
      end
    end

    def set_shoutee
      shoutee_type = params[:shoutee_type]
      shoutee_id = params[:shoutee_id]

      # Skip validation for invite mode
      return if shoutee_type == "invite"

      if shoutee_type.blank? || shoutee_id.blank?
        redirect_to my_shoutouts_path, alert: "Please select a person or group to give a shoutout to."
        return
      end

      @shoutee = case shoutee_type
      when "Person"
                   Person.find_by(id: shoutee_id)
      when "Group"
                   Group.find_by(id: shoutee_id)
      end

      if @shoutee.nil?
        redirect_to my_shoutouts_path, alert: "Could not find the specified person or group."
      elsif @shoutee == Current.user.person
        redirect_to my_shoutouts_path, alert: "You cannot give a shoutout to yourself."
      end
    end

    def shoutout_params
      if params[:shoutout].present?
        params.require(:shoutout).permit(:content)
      else
        # For invite flow, content comes directly
        { content: params[:content] }
      end
    end
  end
end
