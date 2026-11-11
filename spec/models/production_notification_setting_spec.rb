# frozen_string_literal: true

require "rails_helper"

# Who hears about a production: the people on its team with the switch on in
# Production team (Tim, 2026-11-11: messages to Rising Stars reached every
# manager in the organization, whatever the switches said).
RSpec.describe ProductionNotificationSetting do
  let(:production) { create(:production) }
  let(:organization) { production.organization }
  let(:org_manager) { create(:user) }
  let(:prod_manager) { create(:user) }

  before do
    create(:organization_role, organization: organization, user: org_manager, company_role: :manager)
    create(:production_permission, production: production, user: prod_manager, role: :manager)
  end

  def switch(user, on)
    described_class.find_or_initialize_by(production: production, user: user).update!(enabled: on)
  end

  describe ".users_to_notify" do
    it "is only the people with the switch on" do
      switch(prod_manager, true)
      switch(org_manager, false)

      expect(described_class.users_to_notify(production)).to contain_exactly(prod_manager)
    end

    it "is nobody when no switch is on" do
      expect(described_class.users_to_notify(production)).to be_empty
    end

    it "is the whole team when no switch is on and the caller needs someone" do
      users = described_class.users_to_notify(production, whole_team_if_none: true)

      expect(users).to include(org_manager, prod_manager)
    end

    it "keeps to the people with the switch on even when the caller needs someone" do
      switch(prod_manager, true)

      expect(described_class.users_to_notify(production, whole_team_if_none: true)).to contain_exactly(prod_manager)
    end

    it "ignores a switch left on by someone no longer on the team" do
      gone = create(:user)
      switch(gone, true)
      switch(prod_manager, true)

      expect(described_class.users_to_notify(production)).to contain_exactly(prod_manager)
    end
  end
end
