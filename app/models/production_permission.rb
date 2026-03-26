# frozen_string_literal: true

class ProductionPermission < ApplicationRecord
  belongs_to :user
  belongs_to :production

  validates :role, presence: true, inclusion: { in: %w[manager viewer] }
  validates :user_id, uniqueness: { scope: :production_id }

  after_destroy :remove_orphaned_org_role

  private

  # When a member's last production permission in an org is removed,
  # clean up their organization role to prevent a zombie state where
  # they have an org role but can't access anything.
  def remove_orphaned_org_role
    org = production.organization
    return unless org

    org_role = OrganizationRole.find_by(user: user, organization: org)
    return unless org_role&.company_role == "member"

    # Check if they still have any other production permissions in this org
    remaining = user.production_permissions
                    .joins(:production)
                    .where(productions: { organization_id: org.id })
                    .exists?

    org_role.destroy unless remaining
  end
end
