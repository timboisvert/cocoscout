# frozen_string_literal: true

module Manage
  class OrgRolesController < Manage::ManageController
    def index
      # Exclude third-party productions (no casting/roles)
      @productions = Current.organization.productions.type_in_house
                             .includes(:roles)
                             .order(:name)
    end
  end
end
