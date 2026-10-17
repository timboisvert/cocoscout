# frozen_string_literal: true

# Puts someone on a production's team, the one way (the Production Team tab,
# the contract wizard's Team step): someone with a CocoScout account gets the
# organization's "member" role if they have none, a ProductionPermission as
# manager or viewer, and notifications on; someone without one gets an
# emailed invitation that gives them the role when they accept
# (Manage::TeamInvitationsController#do_accept).
class ProductionTeamAdder
  ROLES = %w[manager viewer].freeze
  # outcome: :added, :invited, :already (has a role here), :invited_already
  Result = Data.define(:outcome, :name, :invitation)

  def self.add!(production, role:, by: nil, user: nil, email: nil, name: nil)
    raise ArgumentError, "role must be manager or viewer" unless ROLES.include?(role)

    email = email.to_s.strip.downcase.presence
    user ||= User.find_by(email_address: email) if email
    organization = production.organization

    if user
      # Never echo an outsider's email back: their name, or a stand-in.
      display = user.person&.name.presence || name.to_s.squish.presence || "New team member"
      return Result.new(outcome: :already, name: display, invitation: nil) if role_for(user, production).present?

      unless OrganizationRole.exists?(user: user, organization: organization)
        # Adding someone from outside the organization (picked from the global
        # search) is a legitimate flow; leave an audit trail.
        Rails.logger.info("[cross_org_user_attach] user=#{by&.id} org=#{organization.id} attached_user=#{user.id} via=ProductionTeamAdder")
      end
      OrganizationRole.find_or_create_by!(user: user, organization: organization) { |r| r.company_role = "member" }
      ProductionPermission.create!(user: user, production: production, role: role)
      ProductionNotificationSetting.find_or_create_by!(user: user, production: production) { |s| s.enabled = true }
      return Result.new(outcome: :added, name: display, invitation: nil)
    end

    raise ArgumentError, "an email address is needed to invite someone" unless email&.match?(URI::MailTo::EMAIL_REGEXP)

    existing = TeamInvitation.find_by(email: email, organization: organization, production: production)
    return Result.new(outcome: :invited_already, name: email, invitation: existing) if existing

    invitation = TeamInvitation.create!(email: email, organization: organization, production: production, invitation_role: role)
    Manage::TeamMailer.production_invite(invitation).deliver_later
    Result.new(outcome: :invited, name: email, invitation: invitation)
  end

  # Their role on this production: a ProductionPermission, else a manager or
  # viewer role across the production's organization (found through the
  # production, not Current.organization: a contract can activate outside a
  # request). "member" is no role of its own.
  def self.role_for(user, production)
    permission = user.production_permissions.find_by(production_id: production.id)
    return permission.role if permission

    role = user.organization_roles.find_by(organization_id: production.organization_id)&.company_role
    role == "member" ? nil : role
  end
end
