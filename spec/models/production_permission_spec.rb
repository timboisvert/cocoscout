# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductionPermission, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }

  it "validates role presence and inclusion" do
    permission = ProductionPermission.new(user: user, production: production, role: "manager")
    expect(permission).to be_valid
  end

  it "validates uniqueness of user per production" do
    ProductionPermission.create!(user: user, production: production, role: "manager")
    duplicate = ProductionPermission.new(user: user, production: production, role: "viewer")
    expect(duplicate).not_to be_valid
  end
end
