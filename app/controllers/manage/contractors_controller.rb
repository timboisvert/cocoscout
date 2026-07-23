# frozen_string_literal: true

module Manage
  class ContractorsController < ManageController
    before_action :set_contractor, only: [ :show, :edit, :update, :destroy, :invite, :link_person, :preview_person, :add_person ]

    def index
      @query = params[:q].to_s.strip
      @filter = params[:filter].presence || "all"

      scope = Current.organization.contractors.includes(:contracts).alphabetical
      scope = scope.where("LOWER(name) LIKE ?", "%#{@query.downcase}%") if @query.present?
      all_contractors = scope.to_a

      with_active = all_contractors.select { |c| c.active_contracts.any? }
      without_active = all_contractors - with_active

      # Counts (respect the search, ignore the status filter) for the filter chips
      @total_count = all_contractors.size
      @active_count = with_active.size
      @inactive_count = without_active.size

      @contractors = all_contractors
      case @filter
      when "active"
        @contractors_with_active = with_active
        @contractors_without_active = []
      when "inactive"
        @contractors_with_active = []
        @contractors_without_active = without_active
      else
        @contractors_with_active = with_active
        @contractors_without_active = without_active
      end
    end

    def show
      @active_contracts = @contractor.contracts.status_active.order(:contract_start_date)
      @draft_contracts = @contractor.contracts.status_draft.order(:created_at)
      @completed_contracts = @contractor.contracts.status_completed
        .or(@contractor.contracts.status_cancelled)
        .order(contract_end_date: :desc)
      # A contractor is paid as its backing Person — chosen explicitly by the
      # manager (search-or-invite), never auto-created.
      @person = @contractor.person
      @payment_setup_url = @person && payee_onboarding_url(token: PayeeOnboardingToken.generate(@person))
      @pending_invitation = @person && PersonInvitation.pending.find_by(email: @person.email, organization: Current.organization)
      @has_cocoscout_access = @person&.user.present?
      @invite_preview = @person && !@has_cocoscout_access ? invitation_preview(@person) : nil
    end

    def new
      @contractor = Current.organization.contractors.build
    end

    def create
      @contractor = Current.organization.contractors.build(contractor_params)

      if @contractor.save
        # Link/invite the associated person if chosen on the create form.
        link_or_invite_person!(@contractor)
        notice = @person_link_error ? "Contractor created, but we couldn't link a person: #{@person_link_error}" : "Contractor created."
        respond_to do |format|
          format.html { redirect_to manage_contractor_path(@contractor), notice: notice }
          format.json do
            render json: {
              id: @contractor.id,
              name: @contractor.name,
              email: @contractor.email,
              phone: @contractor.phone,
              address: @contractor.address
            }, status: :created
          end
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: { errors: @contractor.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def edit
    end

    def update
      if @contractor.update(contractor_params)
        redirect_to manage_contractor_path(@contractor), notice: "Contractor updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @contractor.contracts.any?
        redirect_to manage_contractor_path(@contractor), alert: "Cannot delete contractor with existing contracts."
      else
        @contractor.destroy
        redirect_to manage_contractors_path, notice: "Contractor deleted."
      end
    end

    # Invite the contractor to CocoScout: give their backing Person a login so
    # they can see their contracts + set up payment. They land on the talent side
    # with no manager role, so their visibility is limited to their own stuff.
    def invite
      person = @contractor.person
      unless person
        redirect_to manage_contractor_path(@contractor), alert: "Link a person to this contractor first." and return
      end

      send_cocoscout_invitation!(person)
      redirect_to manage_contractor_path(@contractor), notice: "Invitation sent to #{person.email}."
    end

    # Step 2 of the add-a-person modal: show exactly what this person will be
    # sent — an invitation if they're new to CocoScout, a "you've been added"
    # notification if they're already a member — before anything is committed.
    def preview_person
      target = resolve_person_target
      return render_preview_error("Pick a person, or enter a name and email.") unless target

      @preview_person_name = target[:name]
      @preview_person_email = target[:email]
      @preview_person_id = target[:person_id]
      @preview_is_member = target[:person]&.user.present?
      @preview = @preview_is_member ? member_notification_preview(target[:person]) : invitation_preview_for(target[:name], target[:email])
      render partial: "manage/contractors/invite_preview"
    end

    # Confirm from the preview: link the person AND send them the message, in one
    # step. Nothing is created until this is confirmed.
    def add_person
      person = link_or_invite_person!(@contractor)
      return redirect_to(manage_contractor_path(@contractor), alert: @person_link_error || "Pick a person to add.") unless person

      if person.user.present?
        notify_member_added!(person)
        notice = "#{person.name} was added and notified."
      else
        send_cocoscout_invitation!(person)
        notice = "#{person.name} was added and invited to CocoScout."
      end
      redirect_to manage_contractor_path(@contractor), notice: notice
    end

    # Link the contractor to a Person: an existing CocoScout person (person_id) or
    # a brand-new invite (invite_name + invite_email). The reusable search-or-
    # invite picker posts here.
    def link_person
      person = link_or_invite_person!(@contractor)
      if person
        redirect_to manage_contractor_path(@contractor),
                    notice: "#{person.name} is now associated with this contractor."
      elsif @person_link_error
        redirect_to manage_contractor_path(@contractor),
                    alert: "Couldn't link a person: #{@person_link_error}"
      else
        redirect_to manage_contractor_path(@contractor),
                    alert: "Pick a person to link, or enter a name and email to invite someone new."
      end
    end

    # JSON endpoint for autocomplete/search
    def search
      query = params[:q].to_s.strip
      contractors = Current.organization.contractors.alphabetical

      if query.present?
        contractors = contractors.where("LOWER(name) LIKE ?", "%#{query.downcase}%")
      end

      render json: contractors.limit(10).map { |c|
        {
          id: c.id,
          name: c.name,
          email: c.email,
          phone: c.phone,
          address: c.address,
          contracts_count: c.contracts.count
        }
      }
    end

    private

    # Set the contractor's associated Person from the picker's params: an existing
    # person (person_id), or a new invite (invite_email [+ invite_name]). A brand-
    # new invited person is created + sent a CocoScout invitation so they can log
    # in and see their contracts. Returns the Person, or nil if nothing was chosen.
    def link_or_invite_person!(contractor)
      if params[:person_id].present?
        person = Person.find_by(id: params[:person_id])
        return nil unless person

        add_to_org(person)
        contractor.update!(person: person)
        person
      elsif params[:invite_email].present?
        email = params[:invite_email].to_s.strip.downcase
        name = params[:invite_name].to_s.strip.presence || email.split("@").first
        person = Person.where("LOWER(email) = ?", email).first || Person.create!(name: name, email: email)
        add_to_org(person)
        contractor.update!(person: person)
        # Linking just links — the invite is a separate, previewed step, so you
        # always see what's going out before it sends.
        person
      end
    rescue ActiveRecord::RecordInvalid => e
      @person_link_error = e.record.errors.full_messages.to_sentence.presence || e.message
      nil
    end

    def add_to_org(person)
      Current.organization.people << person unless Current.organization.people.include?(person)
    end

    # The exact invitation this person would receive, rendered from the
    # person_invitation content template so the manager can preview it before
    # sending. Read-only — the real setup link is stamped in at send time.
    def invitation_preview(person)
      invitation_preview_for(person.name, person.email)
    end

    def invitation_preview_for(_name, email)
      pending = PersonInvitation.pending.find_by(email: email, organization: Current.organization)
      setup_url = pending ? manage_accept_person_invitations_url(pending.token) : "#"
      rendered = ContentTemplateService.render("person_invitation", {
        organization_name: Current.organization.name,
        setup_url: setup_url
      })
      { subject: rendered[:subject], body: rendered[:body] }
    rescue ContentTemplateService::TemplateNotFoundError => e
      Rails.logger.warn("Contractor invite preview failed: #{e.message}")
      nil
    end

    # What an existing CocoScout member gets when added to a contract — a
    # notification, not an invitation to join.
    def member_notification_preview(_person)
      rendered = ContentTemplateService.render("contract_person_added", {
        organization_name: Current.organization.name,
        contracts_url: my_contracts_url
      })
      { subject: rendered[:subject], body: rendered[:body] }
    rescue ContentTemplateService::TemplateNotFoundError => e
      Rails.logger.warn("Contractor member-notification preview failed: #{e.message}")
      nil
    end

    # Post it as an in-app message (which also rolls into their unread-email
    # digest) so an existing member knows they've been added.
    def notify_member_added!(person)
      copy = member_notification_preview(person)
      return unless copy

      MessageService.send_direct(
        sender: Current.user, recipient_person: person,
        subject: copy[:subject], body: copy[:body],
        organization: Current.organization, system_generated: true
      )
    end

    # Resolve the modal's selection into a target: an existing Person by id, or a
    # name/email pair for someone new. Returns nil when neither is usable.
    def resolve_person_target
      if params[:person_id].present?
        person = Person.find_by(id: params[:person_id])
        person && { person: person, name: person.name, email: person.email, person_id: person.id }
      elsif params[:invite_email].present?
        email = params[:invite_email].to_s.strip.downcase
        name = params[:invite_name].to_s.strip.presence || email.split("@").first
        existing = Person.where("LOWER(email) = ?", email).first
        { person: existing, name: existing&.name || name, email: email, person_id: existing&.id }
      end
    end

    def render_preview_error(message)
      render partial: "manage/contractors/invite_preview_error", locals: { message: message }, status: :unprocessable_entity
    end

    # Give the person a login (if needed) and send them the CocoScout invitation
    # so they can accept, set a password, and see their contracts. Idempotent.
    def send_cocoscout_invitation!(person)
      ensure_login_for(person)
      invitation = PersonInvitation.pending.find_by(email: person.email, organization: Current.organization) ||
                   PersonInvitation.create!(email: person.email, organization: Current.organization)
      Manage::PersonMailer.person_invitation(invitation).deliver_later
    end

    # Give the person a User to log in with (created with a random password; they
    # set it via the invitation link). No-op if they already have one.
    def ensure_login_for(person)
      return if person.user.present?

      user = User.find_by(email_address: person.email.downcase) ||
             User.create!(email_address: person.email.downcase, password: User.generate_secure_password)
      person.update!(user: user)
    end

    def set_contractor
      @contractor = Current.organization.contractors.find(params[:id])
    end

    def contractor_params
      params.require(:contractor).permit(:name, :email, :phone, :address, :notes)
    end
  end
end
