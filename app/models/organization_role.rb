# frozen_string_literal: true

class OrganizationRole < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :person, optional: true

  validates :company_role, presence: true, inclusion: { in: %w[manager viewer member] }

  # Someone who now manages an organization can connect the contracts
  # they're the contractor on to it: they're notified once
  # (ContractConnections.offer!).
  after_commit :offer_manager_their_contracts, on: %i[create update], if: -> { company_role == "manager" && (saved_change_to_company_role? || saved_change_to_id?) }

  def offer_manager_their_contracts
    ContractConnections.offer_all_for(user)
  rescue StandardError => e
    Rails.logger.error("[OrganizationRole] #{id} offer to connect: #{e.class}: #{e.message}")
  end
  validates :user_id, uniqueness: { scope: :organization_id }
  validates :access_template, inclusion: { in: OrganizationAccess::TEMPLATES.keys }, allow_nil: true

  # Access by module (OrganizationAccess): a manager has everything and
  # carries no grants; a viewer carries the grid a template filled in.
  def apply_access!(template:, grants: nil)
    if template == "manager"
      update!(company_role: "manager", access_template: nil, module_grants: {})
    else
      grid = template == "custom" ? OrganizationAccess.normalize(grants) : OrganizationAccess.grants_for_template(template)
      update!(company_role: "viewer", access_template: OrganizationAccess.template_for(grid), module_grants: grid)
    end
  end

  # What to call this person's access on the People page.
  def access_label
    return "Manager" if company_role == "manager"
    return "Viewer" if module_grants.blank?

    OrganizationAccess::TEMPLATES.dig(access_template || OrganizationAccess.template_for(module_grants), :label) || "Custom"
  end

  # Returns the person to display for this role
  # Uses the explicitly set person_id if available, otherwise falls back to user's primary person
  def display_person
    person || user.person
  end
end
