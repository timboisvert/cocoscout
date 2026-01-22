# frozen_string_literal: true

module Manage
  class OrgRolesController < Manage::ManageController
    def index
      @productions = Current.organization.productions
                             .includes(:roles)
                             .order(:name)
    end
  end
end
