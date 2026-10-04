# frozen_string_literal: true

module Manage
  # Who can see a show's ticket sales without being a manager (the show page
  # → Who can see sales): the contractor whose contract includes it, unless
  # the contract says not; people from the production's team and cast; or
  # anyone on CocoScout, found by search, or invited by email when the
  # search finds nobody. A share covers this show or every date of its
  # production. Revoking keeps the record, like door access.
  class TicketSalesViewersController < Manage::TicketingBaseController
    before_action :set_listing

    def index
      @contracts = TicketSalesAccess.contracts_for(@listing)
      @viewers = TicketSalesAccess.viewers_for(@listing).to_a
      @candidates = team_and_cast.reject { |person| manager_user_ids.include?(person.user_id) || viewing_user_ids.include?(person.user_id) }
    end

    def search
      q = params[:q].to_s.strip
      people = if q.length < 2
        []
      else
        like = "%#{Person.sanitize_sql_like(q)}%"
        Person.where.not(user_id: nil).where(archived_at: nil)
              .where("people.name ILIKE :q OR people.email ILIKE :q", q: like)
              .includes(:user).order(:name).limit(30).to_a.uniq(&:user_id).first(15)
      end
      render partial: "manage/ticket_sales_viewers/search_results",
             locals: { listing: @listing, people: people, query: q, viewing_user_ids: viewing_user_ids, manager_user_ids: manager_user_ids }
    end

    # Share with the people ticked from the team and cast, or the one person
    # found by search.
    def create
      people = Person.where(id: Array(params[:person_ids]).compact_blank).or(Person.where(id: params[:person_id].presence)).where.not(user_id: nil).to_a
      return redirect_to(viewers_path, alert: "Choose someone to share the sales with.") if people.empty?

      shared = people.reject { |person| manager_user_ids.include?(person.user_id) }.map do |person|
        viewer = Current.organization.ticket_sales_viewers.active.find_or_initialize_by(user_id: person.user_id, scope: chosen_scope)
        viewer.granted_by ||= Current.user
        viewer.save!
        person.name
      end
      redirect_to viewers_path, notice: shared.any? ? "#{shared.to_sentence} can now see the sales for #{scope_words}." : "Managers already see everything."
    end

    def invite
      email = params[:email].to_s.strip.downcase
      return redirect_to(viewers_path, alert: "Enter an email address to invite.") unless email.match?(URI::MailTo::EMAIL_REGEXP)

      if (user = User.find_by(email_address: email))
        viewer = Current.organization.ticket_sales_viewers.active.find_or_initialize_by(user: user, scope: chosen_scope)
        viewer.granted_by ||= Current.user
        viewer.save!
        return redirect_to(viewers_path, notice: "#{user.person&.name || email} can now see the sales for #{scope_words}.")
      end

      viewer = TicketSalesViewer.invite!(organization: Current.organization, email: email, name: params[:name], scope: chosen_scope, by: Current.user)
      AppMailer.with(template_key: "ticket_sales_invitation", to: email, variables: {
        first_name: viewer.invited_name.to_s.split.first.presence || "there",
        inviter_name: Current.user.person&.name || Current.user.email_address,
        organization_name: Current.organization.name,
        what: scope_words,
        accept_url: ticket_sales_invitation_url(token: viewer.invitation_token)
      }).send_template.deliver_later
      redirect_to viewers_path, notice: "Invitation sent to #{email}."
    end

    # The contractor's automatic view, on or off for this contract.
    def update_contract
      contract = Current.organization.contracts.find(params[:contract_id])
      contract.update!(shares_ticket_sales: params[:shares_ticket_sales] == "1")
      who = contract.contractor&.person&.name || "The contractor"
      redirect_to viewers_path, notice: contract.shares_ticket_sales ? "#{who} sees the sales for their shows." : "#{who} no longer sees the sales."
    end

    def destroy
      viewer = Current.organization.ticket_sales_viewers.active.find(params[:viewer_id])
      viewer.revoke!(Current.user)
      redirect_to viewers_path, notice: "#{viewer.display_name} no longer sees the sales."
    end

    private

    def set_listing
      @listing = Current.organization.ticket_listings.includes(:production, show: :location).find(params[:id])
    end

    def viewers_path
      manage_ticket_listing_viewers_path(@listing)
    end

    # This show, or every date of its production.
    def chosen_scope
      params[:share_scope] == "production" ? @listing.production : @listing
    end

    def scope_words
      params[:share_scope] == "production" ? "every date of #{@listing.production.name}" : "#{@listing.display_title} on #{@listing.show.date_and_time.strftime('%b %-d')}"
    end

    def viewing_user_ids
      @viewing_user_ids ||= TicketSalesAccess.viewers_for(@listing).pluck(:user_id).compact
    end

    def manager_user_ids
      @manager_user_ids ||= Current.organization.organization_roles.where(company_role: "manager").pluck(:user_id) + [ Current.organization.owner_id ]
    end

    # People on the production with CocoScout accounts: its team, then its cast.
    def team_and_cast
      production = @listing.production
      team_user_ids = production.production_permissions.pluck(:user_id)
      cast_ids = production.cast_people.map(&:id)
      Person.where(user_id: team_user_ids).or(Person.where(id: cast_ids)).where.not(user_id: nil).where(archived_at: nil)
            .order(:name).to_a.uniq(&:user_id)
    end
  end
end
