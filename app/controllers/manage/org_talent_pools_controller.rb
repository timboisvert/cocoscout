# frozen_string_literal: true

module Manage
  class OrgTalentPoolsController < Manage::ManageController
    def index
      @productions = Current.organization.productions
                             .includes(talent_pool_members: { memberable: { profile_headshots: { image_attachment: :blob } } })
                             .order(:name)
    end
  end
end
