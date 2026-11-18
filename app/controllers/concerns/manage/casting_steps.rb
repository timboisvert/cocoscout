# frozen_string_literal: true

module Manage
  # The three casting steps two wizards share: who is cast (the talent pool,
  # or names typed in), roles or acts, and the roles themselves. The
  # new-production wizard asks them while a production is being made; Set up
  # casting asks them of one that already exists. The steps' views are
  # manage/casting_steps; this holds what both controllers do with the
  # answers, kept in @wizard_state under the same keys:
  #
  #   :casting_source  "talent_pool", "manual" (or "none", the new-production
  #                    wizard's "We don't cast people in this production")
  #   :casting_mode    "role_based" or "act_based"
  #   :has_roles       "yes" or "no"
  #   :roles           [{ name:, quantity:, category:, standing: }]
  module CastingSteps
    extend ActiveSupport::Concern

    included do
      helper_method :act_based_wizard?, :wizard_casting_source
    end

    private

    # "role_based" or "act_based": whatever the casting-style step stored,
    # falling back to roles.
    def wizard_casting_mode
      mode = @wizard_state[:casting_mode].to_s
      Production.casting_modes.key?(mode) ? mode : "role_based"
    end

    def act_based_wizard?
      wizard_casting_mode == "act_based"
    end

    def wizard_casting_source
      Production.casting_sources.key?(@wizard_state[:casting_source].to_s) ? @wizard_state[:casting_source].to_s : "talent_pool"
    end

    # The roles-or-acts answer. Break rows only make sense in a lineup: they
    # are dropped if the mode flips back, and show roles become plain roles.
    def store_casting_style(mode)
      mode = mode.to_s
      mode = "role_based" unless Production.casting_modes.key?(mode)
      if mode == "role_based" && @wizard_state[:roles].present?
        @wizard_state[:roles] = @wizard_state[:roles]
          .reject { |r| (r[:category] || r["category"]) == Role::BREAK_CATEGORY }
          .map { |r| r.to_h.except(:standing, "standing") }
      end
      @wizard_state[:casting_mode] = mode
    end

    # The roles step's answer. Blank rows are dropped by parse_roles; a "yes"
    # with nothing in it (or an act-mode lineup left empty) is stored as no
    # roles at all.
    def store_roles(has_roles, roles_params)
      roles = has_roles == "yes" ? parse_roles(roles_params) : []
      @wizard_state[:roles] = roles
      @wizard_state[:has_roles] = roles.any? ? "yes" : "no"
    end

    def parse_roles(roles_params)
      return [] if roles_params.blank?

      allowed = act_based_wizard? ? Role::CATEGORIES : (Role::CATEGORIES - [ Role::BREAK_CATEGORY ])

      roles_params.values.map do |role|
        next if role[:name].blank?
        category = role[:category].to_s
        # A show role (MC, Stage Kitten ×2) sits alongside an act-based lineup:
        # not an act, so it may hold several people.
        standing = act_based_wizard? && category == "show_role"
        category = "performing" unless allowed.include?(category)
        # An act (or an intermission) is one thing in the running order.
        quantity = act_based_wizard? && !standing ? 1 : [ (role[:quantity] || 1).to_i, 1 ].max
        row = {
          name: role[:name].to_s.strip,
          quantity: quantity,
          category: category
        }
        row[:standing] = true if standing
        row
      end.compact
    end

    # The stored roles become the production's own (the lineup, in order, for
    # an act-based production; break rows come through as category "break").
    def create_wizard_roles!(production)
      Array(@wizard_state[:roles]).each_with_index do |role_data, index|
        category = role_data[:category] || role_data["category"] || "performing"
        category = "performing" if category == Role::BREAK_CATEGORY && !production.act_based?
        standing = production.act_based? && (role_data[:standing] || role_data["standing"]) ? true : false
        production.roles.create!(
          name: role_data[:name] || role_data["name"],
          quantity: (role_data[:quantity] || role_data["quantity"] || 1).to_i,
          category: category,
          standing: standing,
          position: index + 1,
          restricted: false
        )
      end
    end
  end
end
