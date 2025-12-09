# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductionPermission, type: :model do
  describe "#notifications_enabled?" do
    let(:user) { create(:user) }
    let(:organization) { create(:organization) }
    let(:production) { create(:production, organization: organization) }

    context "when notifications_enabled is explicitly set to true" do
      let(:permission) { ProductionPermission.create!(user: user, production: production, role: "viewer", notifications_enabled: true) }

      it "returns true" do
        expect(permission.notifications_enabled?).to be true
      end
    end

    context "when notifications_enabled is explicitly set to false" do
      let(:permission) { ProductionPermission.create!(user: user, production: production, role: "manager", notifications_enabled: false) }

      it "returns false" do
        expect(permission.notifications_enabled?).to be false
      end
    end

    context "when notifications_enabled is nil (default)" do
      context "and role is manager" do
        let(:permission) { ProductionPermission.create!(user: user, production: production, role: "manager", notifications_enabled: nil) }

        it "returns true (default for managers)" do
          expect(permission.notifications_enabled?).to be true
        end
      end

      context "and role is viewer" do
        let(:permission) { ProductionPermission.create!(user: user, production: production, role: "viewer", notifications_enabled: nil) }

        it "returns false (default for viewers)" do
          expect(permission.notifications_enabled?).to be false
        end
      end
    end
  end
end
